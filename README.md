# hl7v2-gateway

A small, dependency-light bridge between **HL7 v2** systems and **JSON HTTP APIs**.

It listens for HL7 v2 messages over **MLLP**, converts each one to a JSON document, `POST`s it to
an API of your choice, and turns the JSON answer back into an HL7 v2 response — acknowledgement,
results or error — on the same connection.

```
                    ┌───────────────────────── hl7v2-gateway ─────────────────────────┐
  HL7 sender  ──────►  MLLP server ─► Decoder ─► JSON ──► UpstreamClient ──► your API  │
 (LIS, EHR, ...)    │                                                           │     │
              ◄─────┤  MLLP server ◄─ Encoder ◄─ JSON ◄── ResponseBuilder ◄─────┘     │
                    └─────────────────────────────────────────────────────────────────┘
```

The gateway knows nothing about what your API does. Calculators, order routing, patient
look-ups, result storage: anything that can answer a JSON request can sit behind it. The
endpoint is configured with a single environment variable, `UPSTREAM_API_URL`.

Built on [`ruby-hl7`](https://github.com/ruby-hl7/ruby-hl7) for segment parsing and assembly.

## Quick start

Requires Ruby 3.2+.

```bash
bundle install

# 1. an example API (computes a BMI from OBX weight/height segments)
bundle exec ruby examples/mock_api.rb

# 2. the gateway, pointed at it
UPSTREAM_API_URL=http://127.0.0.1:4567/api/messages bundle exec bin/hl7-gateway

# 3. send it an HL7 message
bundle exec bin/hl7-send examples/messages/bmi_request.hl7
```

Request (`examples/messages/bmi_request.hl7`):

```
MSH|^~\&|CLINIC|MAIN-CAMPUS|GATEWAY|HL7GATEWAY|20261012093000||ORM^O01|CTRL-0001|P|2.5
PID|1||MRN48213^^^MAIN-CAMPUS^MR||MARTINEZ^ELENA^R||19840317|F|||41 Harbour Rd^^Porto^^4000-001
ORC|NW|ORD-1001
OBR|1|ORD-1001||BMI^Body mass index^LOCAL
OBX|1|NM|29463-7^Body weight^LN||68.5|kg
OBX|2|NM|8302-2^Body height^LN||172|cm
```

Response:

```
MSH|^~\&|HL7GATEWAY|HL7GATEWAY|CLINIC|MAIN-CAMPUS|20261019104928+0200||ORU^R01|BAF0F8664920|P|2.5||||||UNICODE UTF-8
MSA|AA|CTRL-0001|BMI calculated
PID|1||MRN48213^^^MAIN-CAMPUS^MR||MARTINEZ^ELENA^R||19840317|F|||41 Harbour Rd^^Porto^^4000-001
ORC|RE|ORD-1001|||||||20261019104928
OBR|1|ORD-1001||BMI^Body mass index^LOCAL|||20261019104928||||||||||||||||||F
OBX|1|NM|39156-5^Body mass index^LN||23.2|kg/m2|18.5-24.9|N|||F
OBX|2|ST|BMI-CAT^BMI category||Normal||||||F
```

## Configuration

Everything is read from the environment (see [`.env.example`](.env.example)).

| Variable                  | Default       | Description                                                     |
|---------------------------|---------------|-----------------------------------------------------------------|
| `UPSTREAM_API_URL`        | — (required)  | Endpoint that receives each message as a JSON `POST`.           |
| `UPSTREAM_API_TOKEN`      | —             | Sent as `Authorization: Bearer <token>` when set.               |
| `UPSTREAM_API_TIMEOUT`    | `10`          | Seconds for connect / read / write against the API.             |
| `HL7_HOST`                | `127.0.0.1`   | Interface the MLLP listener binds to.                           |
| `HL7_PORT`                | `2575`        | MLLP listener port.                                             |
| `HL7_SENDING_APPLICATION` | `HL7GATEWAY`  | MSH-3 of every response.                                        |
| `HL7_SENDING_FACILITY`    | `HL7GATEWAY`  | MSH-4 of every response.                                        |
| `HL7_IDLE_TIMEOUT`        | `60`          | Seconds before an idle connection is closed.                    |
| `HL7_MAX_MESSAGE_BYTES`   | `1048576`     | Largest accepted message; bigger ones close the connection.     |
| `LOG_LEVEL`               | `info`        | `debug`, `info`, `warn` or `error`.                             |

Invalid values stop the process at startup with a readable message. The bearer token is redacted
from `Config#inspect`, and message contents are never logged (only type and control id).

## The JSON document

Every HL7 message becomes one document. This is exactly what your API receives:

```json
{
  "message_type": "ORM^O01",
  "control_id": "CTRL-0001",
  "version": "2.5",
  "segments": [
    { "segment": "MSH", "fields": { "sending_application": "CLINIC", "message_type": { "1": "ORM", "2": "O01" } } },
    { "segment": "PID", "fields": { "patient_name": { "1": "MARTINEZ", "2": "ELENA", "3": "R" } } },
    { "segment": "OBX", "fields": {
        "set_id": "1", "value_type": "NM",
        "observation_identifier": { "1": "29463-7", "2": "Body weight", "3": "LN" },
        "observation_value": "68.5", "units": "kg" } }
  ]
}
```

Run `bin/hl7-to-json some_message.hl7` to see the complete document for any message.

**Rules**

- `segments` keeps the original order and repetition of segments. Nothing is dropped.
- Fields use their HL7 v2.5 names for the common segments (MSH, PID, PV1, ORC, OBR, OBX, NTE,
  MSA, ERR, EVN, NK1, AL1, DG1). Any other field, and every field of a custom `Z` segment, is
  exposed positionally as `field_<n>`.
- Empty fields are omitted.
- A field with **components** becomes an object keyed by 1-based position, the same numbering
  HL7 uses (`PID-3.4` is `patient_identifier_list` → `"4"`): `123^^^HOSP^MR` →
  `{"1": "123", "4": "HOSP", "5": "MR"}`. **Sub-components** nest one level further.
- A **repeating** field (`a~b`) becomes an array.
- Escape sequences (`\F\ \S\ \T\ \R\ \E\ \.br\ \Xhh\`) are decoded on the way in and re-applied
  on the way out, so `AT&T | R&D` survives a round trip.
- Delimiters are read from MSH-1/MSH-2, so messages using unusual separators work too.

The conversion is symmetric: `Encoder.call(Decoder.call(message)) == message` for every message
in the test suite (including custom delimiters, repetitions, escapes and non-ASCII text).

## What your API returns

Any `2xx` JSON object. Every field is optional:

```json
{
  "ack_code": "AA",
  "message": "BMI calculated",
  "message_type": "ORU^R01",
  "observations": [
    { "identifier": "39156-5", "text": "Body mass index", "coding_system": "LN",
      "value": 23.2, "units": "kg/m2", "reference_range": "18.5-24.9",
      "abnormal_flags": "N", "value_type": "NM", "status": "F" }
  ],
  "segments": [ { "segment": "ZXT", "fields": { "field_1": "anything else" } } ]
}
```

| Key            | Effect                                                                                       |
|----------------|----------------------------------------------------------------------------------------------|
| `ack_code`     | MSA-1: `AA` (default), `AE`, `AR`, `CA`, `CE` or `CR`. Anything but `AA`/`CA` adds an `ERR`.  |
| `message`      | MSA-3 text (and `ERR-8` for errors).                                                         |
| `message_type` | MSH-9 of the response. Default: `ORU^R01` with observations, `ACK^<event>` without.          |
| `observations` | Each entry becomes an `OBX`. Numbers are `NM`, anything else `ST` unless `value_type` is set. |
| `segments`     | Extra segments in the document format above, appended as they are.                           |

When there are observations the response also carries the request's `PID`, an `ORC` (`RE`) and
an `OBR` that reference the original order, so the receiver can match results to requests.
`ruby-hl7` numbers consecutive repeating segments (`OBX-1`, `OBX-2`, ...).

## Error handling

The gateway never drops a connection because of a bad message; it answers with a negative
acknowledgement and keeps serving.

| Situation                                     | Reply | Notes                                                       |
|-----------------------------------------------|-------|-------------------------------------------------------------|
| Malformed HL7 (no MSH, bad segment, ...)      | `AR`  | `ERR-3` = 100. Addressed to the sender if the MSH is readable. |
| API answers `4xx`                             | `AE`  | MSA-3 / ERR-8 carry the API's `error` or `message` text; the HTTP status goes in `ERR-5`. |
| API unreachable, timeout, `5xx`, bad JSON     | `AR`  | `ERR-3` = 207, generic text. Details only go to the log.    |
| API answer that cannot be rendered as HL7     | `AR`  | e.g. unknown `ack_code`, observation without identifier.    |
| Unexpected exception                          | `AR`  | "Internal gateway error"; the exception is only logged.     |

Transport-level problems (truncated frame, oversized message) close that one connection.

## Command line tools

| Tool                         | Purpose                                                              |
|------------------------------|----------------------------------------------------------------------|
| `bin/hl7-gateway`            | Run the MLLP server. Stops cleanly on `SIGINT`/`SIGTERM`.            |
| `bin/hl7-send FILE`          | MLLP client to try the gateway by hand (`-` reads stdin).            |
| `bin/hl7-to-json [FILE]`     | Print the JSON document of an HL7 message.                           |
| `bin/json-to-hl7 [FILE]`     | Turn a JSON document back into HL7 (`--cr` for real `<CR>` bytes).   |

```bash
bin/hl7-to-json examples/messages/oru_r01.hl7 | bin/json-to-hl7
```

## Running with Docker

```bash
docker compose up --build        # gateway on :2575 in front of the example API
bin/hl7-send examples/messages/bmi_request.hl7
```

To point the container at your own API, set `UPSTREAM_API_URL` and drop the `api` service.

## Design notes

- **MLLP** (`MLLP::Stream`): reassembles frames split across TCP reads, handles several
  messages per connection, tolerates noise between frames and a missing `<CR>` after `<FS>`,
  and enforces a size limit and idle timeout.
- **Sanitizer**: one place that copes with real-world senders: `\n`, `\r\n` or `\r` line
  endings, text before the MSH, blank lines, a BOM, and the character set declared in MSH-18
  (falling back from UTF-8 to ISO-8859-1). Responses are always UTF-8 and say so in MSH-18.
- **What `ruby-hl7` does and what this project adds.** The gem splits a message into typed
  segments and assembles outgoing ones. It does not validate that a message starts with an MSH,
  fails on a trailing empty segment, ignores components, repetitions and escape sequences, and
  numbers MSH fields one position off from the standard. `Decoder`, `Encoder`, `Field`,
  `Escape` and `Schema` fill those gaps.
- **Concurrency**: one thread per connection, answers in order per connection. Shutdown closes
  idle connections immediately and lets in-flight messages finish.
- **Security**: no message content in logs, bearer token redacted, hard limits on message size,
  no redirects followed when calling the API. The listener binds to `127.0.0.1` by default;
  MLLP itself has no authentication or encryption, so put it behind a VPN or TLS terminator
  (stunnel, a service mesh) before exposing it.

## Development

```bash
bundle exec rspec      # 200+ examples, ~3 seconds
bundle exec rubocop
```

The suite covers each layer in isolation (framing, sanitizing, field codec, decoder, encoder,
response builder, HTTP client with WebMock, processor) plus TCP-level server specs and an
end-to-end spec that runs the real gateway in front of the real example API.

```
lib/hl7_gateway/
  config.rb            environment configuration
  mllp.rb              framing + frame reader
  sanitizer.rb         line endings, charset, noise
  delimiters.rb        MSH-1 / MSH-2
  escape.rb            \F\ \S\ \T\ \R\ \E\ \.br\ \Xhh\
  field.rb             field <-> JSON (components, sub-components, repetitions)
  schema.rb            field names per segment
  document.rb          read helpers for JSON documents
  decoder.rb           HL7 -> JSON  (built on ruby-hl7)
  encoder.rb           JSON -> HL7  (built on ruby-hl7)
  response_builder.rb  upstream answer / error -> response document
  upstream_client.rb   HTTP POST with auth, timeouts, error mapping
  processor.rb         the pipeline, and error -> ACK mapping
  server.rb            threaded MLLP listener
examples/              mock API and sample messages
```

## Contributing

Contributions are very welcome, and **any pull request is appreciated**: bug fixes, new
segment names in `Schema`, better docs, extra tests, or ideas for making the gateway more
useful. If you are unsure whether something fits, open an issue first and let's talk.

1. Fork the repository and create a branch (`git checkout -b my-change`).
2. Make your change, with specs that cover it.
3. Run `bundle exec rspec` and `bundle exec rubocop`; both should pass.
4. Open a pull request describing what changed and why.

New to HL7 v2? Small, well-scoped improvements are a great way in: for example naming the
fields of another segment in `lib/hl7_gateway/schema.rb`, or adding a sample message to
`examples/messages`.

## License

MIT © Franco Galiotti
