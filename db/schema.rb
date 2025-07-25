# frozen_string_literal: true

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

ActiveRecord::Schema[7.0].define(version: 20_241_203_163_430) do
  # These are extensions that must be enabled in order to support this database
  enable_extension 'plpgsql'

  create_table 'bookings', force: :cascade do |t|
    t.integer 'dossier'
    t.string 'user'
    t.bigint 'session_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[dossier user session_id], name: 'index_bookings_on_dossier_and_user_and_session_id', unique: true
    t.index ['session_id'], name: 'index_bookings_on_session_id'
  end

  create_table 'checks', force: :cascade do |t|
    t.integer 'dossier'
    t.string 'checker'
    t.datetime 'created_at', precision: nil, null: false
    t.datetime 'updated_at', precision: nil, null: false
    t.datetime 'checked_at', precision: nil
    t.bigint 'version', default: 1
    t.integer 'demarche_id'
    t.boolean 'failed'
    t.boolean 'posted', default: false
    t.index %w[dossier checker], name: 'unicity', unique: true
    t.index ['dossier'], name: 'by_dossier'
  end

  create_table 'delayed_jobs', force: :cascade do |t|
    t.integer 'priority', default: 0, null: false
    t.integer 'attempts', default: 0, null: false
    t.text 'handler', null: false
    t.text 'last_error'
    t.datetime 'run_at', precision: nil
    t.datetime 'locked_at', precision: nil
    t.datetime 'failed_at', precision: nil
    t.string 'locked_by'
    t.string 'queue'
    t.datetime 'created_at', precision: nil
    t.datetime 'updated_at', precision: nil
    t.string 'cron'
    t.index %w[priority run_at], name: 'delayed_jobs_priority'
  end

  create_table 'demarches', force: :cascade do |t|
    t.string 'libelle'
    t.datetime 'checked_at', precision: nil
    t.datetime 'created_at', precision: nil, null: false
    t.datetime 'updated_at', precision: nil, null: false
    t.string 'instructeur'
    t.string 'configuration'
  end

  create_table 'demarches_users', id: false, force: :cascade do |t|
    t.bigint 'demarche_id', null: false
    t.bigint 'user_id', null: false
    t.index %w[user_id demarche_id], name: 'index_demarches_users_on_user_id_and_demarche_id'
  end

  create_table 'dossier_data', force: :cascade do |t|
    t.integer 'dossier', null: false
    t.string 'label', null: false
    t.jsonb 'data', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[dossier label], name: 'index_dossier_data_on_dossier_and_label', unique: true
  end

  create_table 'messages', force: :cascade do |t|
    t.string 'message'
    t.datetime 'created_at', precision: nil, null: false
    t.datetime 'updated_at', precision: nil, null: false
    t.bigint 'check_id'
    t.string 'field'
    t.string 'value'
    t.index ['check_id'], name: 'index_messages_on_check_id'
  end

  create_table 'scheduled_tasks', force: :cascade do |t|
    t.integer 'dossier'
    t.string 'task'
    t.text 'parameters'
    t.datetime 'run_at', precision: nil
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[dossier task run_at], name: 'st_unicity', unique: true
    t.index ['run_at'], name: 'by_date'
  end

  create_table 'sessions', force: :cascade do |t|
    t.string 'name'
    t.datetime 'date', precision: nil
    t.integer 'capacity'
    t.integer 'bookings_count', default: 0, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[name date], name: 'index_sessions_on_name_and_date', unique: true
  end

  create_table 'syncs', force: :cascade do |t|
    t.string 'job'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
  end

  create_table 'users', force: :cascade do |t|
    t.string 'email', default: '', null: false
    t.string 'encrypted_password', default: '', null: false
    t.string 'reset_password_token'
    t.datetime 'reset_password_sent_at', precision: nil
    t.datetime 'remember_created_at', precision: nil
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.integer 'sign_in_count', default: 0, null: false
    t.datetime 'current_sign_in_at', precision: nil
    t.datetime 'last_sign_in_at', precision: nil
    t.string 'current_sign_in_ip'
    t.string 'last_sign_in_ip'
    t.string 'confirmation_token'
    t.datetime 'confirmed_at', precision: nil
    t.datetime 'confirmation_sent_at', precision: nil
    t.string 'unconfirmed_email'
    t.integer 'failed_attempts', default: 0, null: false
    t.string 'unlock_token'
    t.datetime 'locked_at', precision: nil
    t.index ['confirmation_token'], name: 'index_users_on_confirmation_token', unique: true
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index ['reset_password_token'], name: 'index_users_on_reset_password_token', unique: true
    t.index ['unlock_token'], name: 'index_users_on_unlock_token', unique: true
  end
end
