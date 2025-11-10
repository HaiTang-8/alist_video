-- public.t_favorite_directories definition

-- Drop table

-- DROP TABLE t_favorite_directories;

CREATE TABLE t_favorite_directories (
                                        id serial4 NOT NULL,
                                        "path" text NOT NULL,
                                        "name" text NOT NULL,
                                        user_id int4 NOT NULL,
                                        created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
                                        CONSTRAINT t_favorite_directories_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_favorite_directories_unique ON public.t_favorite_directories USING btree (user_id, path);
CREATE INDEX idx_favorite_directories_user_id ON public.t_favorite_directories USING btree (user_id);


-- public.t_historical_records definition

-- Drop table

-- DROP TABLE t_historical_records;

CREATE TABLE t_historical_records (
                                      video_sha1 varchar(32) NOT NULL, -- 文件sha1的值
                                      video_path varchar(2000) NULL, -- 文件路径
                                      video_seek int4 NULL, -- 视频播放进度(单位s）
                                      user_id int4 NULL, -- 用户id
                                      change_time timestamp(6) NULL, -- 更改时间
                                      video_name varchar(1000) NULL, -- 文件名
                                      total_video_duration int4 NULL, -- 视频总时长(单位S)
                                      screenshot bytea NULL,
                                      CONSTRAINT t_historical_records_pk PRIMARY KEY (video_sha1),
                                      CONSTRAINT unique_video_user UNIQUE (video_sha1, user_id)
);
COMMENT ON TABLE public.t_historical_records IS '历史记录表';

-- Column comments

COMMENT ON COLUMN public.t_historical_records.video_sha1 IS '文件sha1的值';
COMMENT ON COLUMN public.t_historical_records.video_path IS '文件路径';
COMMENT ON COLUMN public.t_historical_records.video_seek IS '视频播放进度(单位s）';
COMMENT ON COLUMN public.t_historical_records.user_id IS '用户id';
COMMENT ON COLUMN public.t_historical_records.change_time IS '更改时间';
COMMENT ON COLUMN public.t_historical_records.video_name IS '文件名';
COMMENT ON COLUMN public.t_historical_records.total_video_duration IS '视频总时长(单位S)';