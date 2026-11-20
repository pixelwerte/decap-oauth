FROM rust:1.100.0-bookworm AS builder
WORKDIR /app
RUN apt-get update
RUN apt-get install -y musl-tools
RUN rustup target add x86_64-unknown-linux-musl

RUN USER=root cargo new decap_oauth
WORKDIR /app/decap_auth

COPY src ./src

COPY Cargo.toml Cargo.lock ./
RUN cargo install --locked --target x86_64-unknown-linux-musl --path .

FROM builder AS sbom
USER root
COPY --from=anchore/syft@sha256:e97e20b6e6d1699c60296b66ab337941724f9bd06ac279d893eda89601fc4b2a /syft /usr/local/bin/syft
RUN SYFT_CHECK_FOR_APP_UPDATE=false syft dir:/app/decap_auth --exclude './kaniko' --exclude './.app_platform' --exclude './.app_platform_workspace' -o cyclonedx-json=/sbom.cdx.json

FROM amazon/aws-cli:2.41.2@sha256:7a77ccb39e3272191adbf905c50db8c127db88fd79454911a41a6b1c0e419e9b AS sbom-upload
ARG SBOM_SPACES_BUCKET
ARG SBOM_SPACES_ENDPOINT
ARG SBOM_SPACES_KEY
ARG SBOM_SPACES_SECRET
COPY --from=sbom /sbom.cdx.json /sbom.cdx.json
RUN if [ -n "$SBOM_SPACES_BUCKET" ]; then \
      AWS_ACCESS_KEY_ID="$SBOM_SPACES_KEY" AWS_SECRET_ACCESS_KEY="$SBOM_SPACES_SECRET" AWS_DEFAULT_REGION=us-east-1 \
      aws s3 cp /sbom.cdx.json "s3://$SBOM_SPACES_BUCKET/sbom/decap-oauth/Dockerfile/$(date -u +%Y%m%dT%H%M%SZ).cdx.json" --endpoint-url "$SBOM_SPACES_ENDPOINT"; \
    fi && touch /tmp/sbom.done

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/local/cargo/bin/decap_oauth .
USER 1000
CMD ["./decap_oauth"]
COPY --from=sbom-upload /tmp/sbom.done /.sbom-upload-done
