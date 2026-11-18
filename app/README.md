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
