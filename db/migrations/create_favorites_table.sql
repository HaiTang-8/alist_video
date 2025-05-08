-- Create favorites table
CREATE TABLE IF NOT EXISTS t_favorite_directories (
  id SERIAL PRIMARY KEY,
  path TEXT NOT NULL,
  name TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add index on user_id for better query performance
CREATE INDEX IF NOT EXISTS idx_favorite_directories_user_id ON t_favorite_directories(user_id);

-- Create a unique constraint to prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_favorite_directories_unique ON t_favorite_directories(user_id, path); 