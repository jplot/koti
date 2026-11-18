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

Then import `plan.json` with `PUT /api/plan`. Windows get a 50 cm sill, the hypothesis of the architect-plan page until it is measured, and their head is the sill plus the model's height. When the model gives no head, doors get 204 cm and windows without a height 215 cm. Correct them in `plan.json` first. A real home's plan stays out of this repository.
