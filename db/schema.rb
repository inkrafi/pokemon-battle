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

ActiveRecord::Schema[7.1].define(version: 2026_10_25_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "card_sets", force: :cascade do |t|
    t.string "tcgdex_id", null: false
    t.string "name", null: false
    t.date "released_on"
    t.integer "card_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tcgdex_id"], name: "index_card_sets_on_tcgdex_id", unique: true
  end

  create_table "cards", force: :cascade do |t|
    t.bigint "card_set_id", null: false
    t.string "tcgdex_id", null: false
    t.string "number", null: false
    t.string "name", null: false
    t.string "supertype", null: false
    t.string "subtype"
    t.integer "hp"
    t.string "energy_types", default: [], null: false, array: true
    t.string "evolves_from"
    t.integer "retreat_cost"
    t.string "weakness_type"
    t.integer "weakness_multiplier"
    t.string "resistance_type"
    t.integer "resistance_amount"
    t.integer "prize_value", default: 1, null: false
    t.boolean "ace_spec", default: false, null: false
    t.string "regulation_mark"
    t.boolean "standard_legal", default: false, null: false
    t.string "rarity"
    t.jsonb "attacks", default: [], null: false
    t.jsonb "abilities", default: [], null: false
    t.boolean "playable", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "effects", default: [], null: false
    t.string "image_url"
    t.index ["card_set_id"], name: "index_cards_on_card_set_id"
    t.index ["name"], name: "index_cards_on_name"
    t.index ["playable"], name: "index_cards_on_playable"
    t.index ["supertype", "subtype"], name: "index_cards_on_supertype_and_subtype"
    t.index ["tcgdex_id"], name: "index_cards_on_tcgdex_id", unique: true
  end

  create_table "deck_cards", force: :cascade do |t|
    t.bigint "deck_id", null: false
    t.bigint "card_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_deck_cards_on_card_id"
    t.index ["deck_id", "card_id"], name: "index_deck_cards_on_deck_id_and_card_id", unique: true
    t.index ["deck_id"], name: "index_deck_cards_on_deck_id"
  end

  create_table "decks", force: :cascade do |t|
    t.bigint "player_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "sample", default: false, null: false
    t.index ["player_id"], name: "index_decks_on_player_id"
  end

  create_table "games", force: :cascade do |t|
    t.bigint "player0_id"
    t.bigint "player1_id"
    t.jsonb "state", default: {}, null: false
    t.string "status", default: "setup", null: false
    t.integer "winner_seat"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mode", default: "hotseat", null: false
    t.bigint "host_deck_id"
    t.string "invite_token"
    t.index ["host_deck_id"], name: "index_games_on_host_deck_id"
    t.index ["invite_token"], name: "index_games_on_invite_token", unique: true
    t.index ["player0_id"], name: "index_games_on_player0_id"
    t.index ["player1_id"], name: "index_games_on_player1_id"
  end

  create_table "players", force: :cascade do |t|
    t.string "token", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_players_on_token", unique: true
  end

  add_foreign_key "cards", "card_sets"
  add_foreign_key "deck_cards", "cards"
  add_foreign_key "deck_cards", "decks"
  add_foreign_key "decks", "players"
  add_foreign_key "games", "decks", column: "host_deck_id", on_delete: :nullify
  add_foreign_key "games", "players", column: "player0_id"
  add_foreign_key "games", "players", column: "player1_id"
end
