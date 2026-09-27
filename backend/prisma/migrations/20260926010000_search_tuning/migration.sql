-- Typo tolerance for Uzbek/Russian queries ("cobolt" → "cobalt" scores ~0.43).
-- The default word-similarity threshold (0.6) is too strict for short words.
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET pg_trgm.word_similarity_threshold = 0.4', current_database());
END
$$;
