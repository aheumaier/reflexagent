# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_05_08_162332) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "code_repositories", force: :cascade do |t|
    t.string "name", null: false
    t.string "url"
    t.string "provider", default: "github", null: false
    t.bigint "team_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "provider"], name: "index_code_repositories_on_name_and_provider", unique: true
    t.index ["name"], name: "index_code_repositories_on_name"
    t.index ["team_id"], name: "index_code_repositories_on_team_id"
  end

  create_table "domain_alerts", force: :cascade do |t|
    t.string "name", null: false
    t.string "severity", null: false
    t.jsonb "metric_data", default: {}, null: false
    t.float "threshold", null: false
    t.string "status", default: "active", null: false
    t.datetime "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_domain_alerts_on_name"
    t.index ["severity"], name: "index_domain_alerts_on_severity"
    t.index ["status"], name: "index_domain_alerts_on_status"
  end

  create_table "domain_events", force: :cascade do |t|
    t.uuid "aggregate_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigserial "position", null: false
    t.index ["aggregate_id", "position"], name: "index_domain_events_on_aggregate_id_and_position"
    t.index ["aggregate_id"], name: "index_domain_events_on_aggregate_id"
    t.index ["event_type"], name: "index_domain_events_on_event_type"
    t.index ["position"], name: "index_domain_events_on_position", unique: true
  end

  create_table "metrics", primary_key: ["id", "recorded_at"], force: :cascade do |t|
    t.bigserial "id", null: false
    t.text "name", null: false
    t.float "value", null: false
    t.text "source", null: false
    t.jsonb "dimensions"
    t.timestamptz "recorded_at", default: -> { "now()" }, null: false
    t.index ["dimensions"], name: "idx_metrics_dimensions", using: :gin
    t.index ["dimensions"], name: "idx_metrics_dimensions_path_ops", opclass: :jsonb_path_ops, using: :gin
    t.index ["name", "recorded_at"], name: "metrics_name_recorded_at_idx"
    t.index ["name", "source", "recorded_at"], name: "idx_metrics_name_source_recorded_at"
    t.index ["name"], name: "idx_metrics_name"
    t.index ["name"], name: "metrics_name_idx"
    t.index ["recorded_at"], name: "metrics_recorded_at_idx"
    t.index ["source"], name: "idx_metrics_source"
  end

  create_table "metrics_2025_04", primary_key: ["id", "recorded_at"], force: :cascade do |t|
    t.bigint "id", null: false
    t.text "name", null: false
    t.float "value", null: false
    t.text "source", null: false
    t.jsonb "dimensions"
    t.timestamptz "recorded_at", default: -> { "now()" }, null: false
    t.index ["name", "recorded_at"], name: "metrics_2025_04_name_recorded_at_idx"
    t.index ["name"], name: "metrics_2025_04_name_idx"
    t.index ["recorded_at"], name: "metrics_2025_04_recorded_at_idx"
  end

  create_table "metrics_2025_05", primary_key: ["id", "recorded_at"], force: :cascade do |t|
    t.bigint "id", default: -> { "nextval('metrics_id_seq'::regclass)" }, null: false
    t.text "name", null: false
    t.float "value", null: false
    t.text "source", null: false
    t.jsonb "dimensions"
    t.timestamptz "recorded_at", default: -> { "now()" }, null: false
    t.index ["dimensions"], name: "metrics_2025_05_dimensions_idx", using: :gin
    t.index ["dimensions"], name: "metrics_2025_05_dimensions_idx1", opclass: :jsonb_path_ops, using: :gin
    t.index ["name", "recorded_at"], name: "metrics_2025_05_name_recorded_at_idx"
    t.index ["name", "source", "recorded_at"], name: "metrics_2025_05_name_source_recorded_at_idx"
    t.index ["name"], name: "metrics_2025_05_name_idx"
    t.index ["name"], name: "metrics_2025_05_name_idx1"
    t.index ["recorded_at"], name: "metrics_2025_05_recorded_at_idx"
    t.index ["source"], name: "metrics_2025_05_source_idx"
  end

  create_table "metrics_2025_06", primary_key: ["id", "recorded_at"], force: :cascade do |t|
    t.bigint "id", default: -> { "nextval('metrics_id_seq'::regclass)" }, null: false
    t.text "name", null: false
    t.float "value", null: false
    t.text "source", null: false
    t.jsonb "dimensions"
    t.timestamptz "recorded_at", default: -> { "now()" }, null: false
    t.index ["dimensions"], name: "metrics_2025_06_dimensions_idx", using: :gin
    t.index ["dimensions"], name: "metrics_2025_06_dimensions_idx1", opclass: :jsonb_path_ops, using: :gin
    t.index ["name", "recorded_at"], name: "metrics_2025_06_name_recorded_at_idx"
    t.index ["name", "source", "recorded_at"], name: "metrics_2025_06_name_source_recorded_at_idx"
    t.index ["name"], name: "metrics_2025_06_name_idx"
    t.index ["name"], name: "metrics_2025_06_name_idx1"
    t.index ["recorded_at"], name: "metrics_2025_06_recorded_at_idx"
    t.index ["source"], name: "metrics_2025_06_source_idx"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_teams_on_slug", unique: true
  end

  add_foreign_key "code_repositories", "teams"
end
