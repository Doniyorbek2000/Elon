import { Injectable } from '@nestjs/common';
import { AttributeType, Category, CategoryAttribute, CategoryKind, Prisma } from '@prisma/client';

import { AppError } from '../../common/errors';
import { apiEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';

type CategoryWithAttributes = Category & { attributes: CategoryAttribute[] };

interface Catalog {
  byId: Map<string, CategoryWithAttributes>;
  children: Map<string | null, CategoryWithAttributes[]>;
  loadedAt: number;
}

export interface NormalizedAttribute {
  attributeId: string;
  valueText: string | null;
  valueNumber: number | null;
  valueBool: boolean | null;
  valueList: string[];
}

/**
 * Category taxonomy + attribute schemas. The tree is small and read-heavy, so
 * it is cached in memory and refreshed every few minutes.
 */
@Injectable()
export class CategoriesService {
  private catalog?: Catalog;

  constructor(private readonly prisma: PrismaService) {}

  private async load(): Promise<Catalog> {
    if (this.catalog && Date.now() - this.catalog.loadedAt < 5 * 60_000) return this.catalog;
    const rows = await this.prisma.category.findMany({
      where: { isActive: true },
      include: { attributes: { orderBy: { sortOrder: 'asc' } } },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
    const byId = new Map(rows.map((r) => [r.id, r]));
    const children = new Map<string | null, CategoryWithAttributes[]>();
    for (const row of rows) {
      const list = children.get(row.parentId) ?? [];
      list.push(row);
      children.set(row.parentId, list);
    }
    this.catalog = { byId, children, loadedAt: Date.now() };
    return this.catalog;
  }

  invalidate(): void {
    this.catalog = undefined;
  }

  async get(id: string): Promise<CategoryWithAttributes> {
    const category = (await this.load()).byId.get(id);
    if (!category) throw AppError.validation('Unknown category', { field: 'categoryId' });
    return category;
  }

  /** Listings attach to leaf categories only (e.g. "Yengil avtomobillar", not "Transport"). */
  async isLeaf(id: string): Promise<boolean> {
    return ((await this.load()).children.get(id) ?? []).length === 0;
  }

  async root(id: string): Promise<CategoryWithAttributes> {
    const catalog = await this.load();
    let current = catalog.byId.get(id);
    while (current?.parentId) current = catalog.byId.get(current.parentId);
    if (!current) throw AppError.validation('Unknown category', { field: 'categoryId' });
    return current;
  }

  /** The category and all its descendants (for "Avtomobil" → cars, parts, …). */
  async subtreeIds(id: string): Promise<string[]> {
    const catalog = await this.load();
    if (!catalog.byId.has(id)) throw AppError.validation('Unknown category', { field: 'categoryId' });
    const ids: string[] = [];
    const stack = [id];
    while (stack.length) {
      const next = stack.pop()!;
      ids.push(next);
      for (const child of catalog.children.get(next) ?? []) stack.push(child.id);
    }
    return ids;
  }

  /** Leaf attributes, or the nearest ancestor's when the leaf defines none. */
  /**
   * Attributes are defined per category (no inheritance): a parent's form
   * (e.g. car brand/year) must not leak into siblings like "Ehtiyot qismlar".
   */
  async effectiveAttributes(id: string): Promise<CategoryAttribute[]> {
    return (await this.get(id)).attributes;
  }

  async effectiveSchema(id: string): Promise<CategoryWithAttributes> {
    return this.get(id);
  }

  /**
   * Validates attribute input against the category schema and returns typed
   * rows. Unknown keys are rejected so clients can't smuggle arbitrary data.
   */
  async validateAttributes(categoryId: string, input: Record<string, unknown>): Promise<NormalizedAttribute[]> {
    const fields = await this.effectiveAttributes(categoryId);
    const byKey = new Map(fields.map((f) => [f.key, f]));
    const errors: Record<string, string> = {};
    for (const key of Object.keys(input)) if (!byKey.has(key)) errors[key] = 'Unknown attribute';

    const result: NormalizedAttribute[] = [];
    for (const field of fields) {
      const raw = input[field.key];
      const empty = raw == null || raw === '' || (Array.isArray(raw) && raw.length === 0);
      if (empty) {
        if (field.required) errors[field.key] = `${field.label} is required`;
        continue;
      }
      const row: NormalizedAttribute = { attributeId: field.id, valueText: null, valueNumber: null, valueBool: null, valueList: [] };
      switch (field.type) {
        case AttributeType.NUMBER: {
          const value = typeof raw === 'number' ? raw : Number(String(raw).replace(/\s/g, ''));
          if (!Number.isFinite(value)) errors[field.key] = 'Must be a number';
          else if (field.min != null && value < field.min) errors[field.key] = `Minimum is ${field.min}`;
          else if (field.max != null && value > field.max) errors[field.key] = `Maximum is ${field.max}`;
          row.valueNumber = value;
          break;
        }
        case AttributeType.BOOLEAN: {
          const value = raw === true || raw === 'true' ? true : raw === false || raw === 'false' ? false : null;
          if (value === null) errors[field.key] = 'Must be true or false';
          row.valueBool = value;
          break;
        }
        case AttributeType.SELECT:
          if (typeof raw !== 'string' || !field.options.includes(raw)) errors[field.key] = 'Choose one of the options';
          row.valueText = String(raw);
          break;
        case AttributeType.MULTI_SELECT:
          if (!Array.isArray(raw) || raw.some((v) => typeof v !== 'string' || !field.options.includes(v))) {
            errors[field.key] = 'Choose from the options';
          }
          row.valueList = Array.isArray(raw) ? raw.map(String) : [];
          break;
        case AttributeType.TEXT:
          if (typeof raw !== 'string' || raw.length > 200) errors[field.key] = 'Text up to 200 characters';
          row.valueText = String(raw).trim();
          break;
      }
      result.push(row);
    }
    if (Object.keys(errors).length) throw AppError.validation('Invalid attributes', { fields: errors });
    return result;
  }

  async tree(kind?: CategoryKind) {
    const catalog = await this.load();
    const present = (c: CategoryWithAttributes): unknown => ({
      id: c.id,
      parentId: c.parentId,
      kind: apiEnum(c.kind),
      name: c.name,
      subtitle: c.subtitle,
      iconKey: c.iconKey,
      tone: c.tone,
      homeShortcut: c.homeShortcut,
      schema: {
        priceMode: apiEnum(c.priceMode),
        supportsCondition: c.supportsCondition,
        photosRequired: c.photosRequired,
        allowUsd: c.allowUsd,
        titleHint: c.titleHint,
        fields: c.attributes.map((a) => ({
          key: a.key,
          label: a.label,
          type: apiEnum(a.type),
          required: a.required,
          filterable: a.filterable,
          unit: a.unit,
          min: a.min,
          max: a.max,
          hint: a.hint,
          options: a.options,
        })),
      },
      children: (catalog.children.get(c.id) ?? []).map(present),
    });
    return (catalog.children.get(null) ?? []).filter((c) => !kind || c.kind === kind).map(present);
  }

  /** Human label/value pairs for presenting a listing's attributes. */
  static presentAttributes(
    rows: Array<Prisma.ListingAttributeGetPayload<{ include: { attribute: true } }>>,
  ): Array<{ key: string; label: string; value: string }> {
    return rows
      .sort((a, b) => a.attribute.sortOrder - b.attribute.sortOrder)
      .map((row) => {
        const { attribute } = row;
        let value: string;
        if (row.valueNumber != null) {
          const formatted = Number.isInteger(row.valueNumber)
            ? row.valueNumber.toLocaleString('en-US').replace(/,/g, ' ')
            : String(row.valueNumber);
          value = attribute.unit ? `${formatted} ${attribute.unit}` : formatted;
        } else if (row.valueBool != null) value = row.valueBool ? 'Ha' : 'Yo‘q';
        else if (row.valueList.length) value = row.valueList.join(', ');
        else value = row.valueText ?? '';
        return { key: attribute.key, label: attribute.label, value };
      });
  }
}
