# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_07_09_024020) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "checks", force: :cascade do |t|
    t.integer "dossier"
    t.string "checker"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "checked_at"
    t.float "version", default: 1.0
    t.integer "demarche_id"
    t.boolean "failed"
    t.boolean "posted", default: false
    t.index ["dossier", "checker"], name: "unicity", unique: true
    t.index ["dossier"], name: "by_dossier"
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "cron"
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "demarches", force: :cascade do |t|
    t.string "libelle"
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "instructeur"
    t.string "configuration"
  end

  create_table "messages", force: :cascade do |t|
    t.string "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "check_id"
    t.string "field"
    t.string "value"
    t.index ["check_id"], name: "index_messages_on_check_id"
  end

end
