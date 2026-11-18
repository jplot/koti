# syntax=docker/dockerfile:1
# Built from the repository root: docker build -f deploy/Dockerfile .

FROM node:26-slim AS front
WORKDIR /koti/front
COPY front/package.json front/package-lock.json ./
RUN npm ci
COPY front/ ./
# The type check reads catalog/ (the example plan and the schema the tests import).
COPY catalog/ /koti/catalog/
RUN npm run build

FROM ruby:4.0-slim AS gems
RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev \
  && rm -rf /var/lib/apt/lists/*
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test BUNDLE_PATH=/usr/local/bundle
WORKDIR /koti/app
COPY app/Gemfile app/Gemfile.lock ./
RUN bundle install && rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache

FROM ruby:4.0-slim
RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y libpq5 libyaml-0-2 \
  && rm -rf /var/lib/apt/lists/*
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test BUNDLE_PATH=/usr/local/bundle
WORKDIR /koti/app
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY app/ ./
# KotiPlan reads its schema from ../catalog, beside the app.
COPY catalog/ /koti/catalog/
COPY --from=front /koti/front/dist/ ./public/
COPY deploy/docker-entrypoint /usr/local/bin/docker-entrypoint
RUN groupadd --system --gid 1000 koti \
  && useradd --system --uid 1000 --gid koti --create-home koti \
  && mkdir -p log tmp \
  && chown -R koti:koti log tmp
USER koti
EXPOSE 3000
ENTRYPOINT ["docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
