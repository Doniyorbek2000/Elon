import { Injectable } from '@nestjs/common';
import type { Server } from 'socket.io';

/**
 * Realtime fan-out used by domain services without depending on the gateway: services publish events to
 * user rooms; with the Redis adapter this fans out across API instances.
 */
@Injectable()
export class ChatEmitter {
  private server?: Server;

  attach(server: Server): void {
    this.server = server;
  }

  toUsers(userIds: string[], event: string, payload: unknown): void {
    if (!this.server || userIds.length === 0) return;
    this.server.to(userIds.map((id) => `user:${id}`)).emit(event, payload);
  }

  toRoom(room: string, event: string, payload: unknown): void {
    this.server?.to(room).emit(event, payload);
  }

  /** Closes sockets authenticated with revoked sessions (all instances). */
  disconnectSessions(sessionIds: string[]): void {
    if (!this.server || sessionIds.length === 0) return;
    this.server.in(sessionIds.map((id) => `session:${id}`)).disconnectSockets(true);
  }
}
