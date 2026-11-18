# koti web

The Rails 8.1 API behind koti, in API mode on PostgreSQL. It runs on Ruby 4.0.

## Develop

```sh
cd app
bundle install
bin/rails db:prepare
bundle exec rake
```

`bundle exec rake` runs RuboCop, RSpec with coverage, the YARD documentation check, RBS validation and Steep. It must pass before every commit.

In development and test, the database is read from `DB_HOST`, `DB_USER` and `DB_PASSWORD`. They default to `localhost`, `postgres` and `postgres`. Production reads `DATABASE_URL` and `SECRET_KEY_BASE`.

## Accounts

There is no sign-up page. Create an account from the console:

```sh
bin/rails runner 'User.create!(email_address: "ana@example.com", password: "…")'
```

The front signs in with `POST /api/session` and keeps the signed `session_id` cookie.

## Plans

koti reads a home plan in the koti-plan format (`../catalog/koti-plan.schema.json`, example in `../catalog/examples/studio.json`). `PUT /api/plan` imports one, and `GET /api/plan` serves the latest.

To start from the `model.json` of the architect-plan scripts:

```sh
bin/rails 'koti:plan:from_model[path/to/model.json,Appartement]' > plan.json
```

Then import `plan.json` from the front. When the model has no height for an opening, doors get a 204 cm head and windows a 90 cm sill and a 215 cm head: correct them in `plan.json` first. A real home's plan stays out of this repository.
