FROM ruby:3.2-slim

ENV BUNDLE_WITHOUT="development:test:examples" \
    BUNDLE_DEPLOYMENT="true"

WORKDIR /app

COPY Gemfile Gemfile.lock hl7_gateway.gemspec ./
COPY lib/hl7_gateway/version.rb lib/hl7_gateway/version.rb
RUN bundle install

COPY . .

RUN useradd --system --no-create-home gateway
USER gateway

ENV HL7_HOST=0.0.0.0 \
    HL7_PORT=2575
EXPOSE 2575

CMD ["bin/hl7-gateway"]
