# Database seeds for self-hosted Ricqchet.
#
# Run with:
#
#     mix run priv/repo/seeds.exs
#
# (also invoked automatically by `mix ecto.setup` / `mix setup`).
#
# This is idempotent and safe to run multiple times. It ensures the single
# default tenant and an initial admin user exist.
#
# Configure the initial admin via environment variables:
#
#     ADMIN_EMAIL     the admin's email address (default: admin@localhost)
#     ADMIN_PASSWORD  the admin's password; if unset, a secure password is
#                     generated and printed once
#
# After first run, sign in and change the password immediately (Settings →
# Change password, or POST /v1/auth/change-password). If you lose access, run:
#
#     mix ricqchet.reset_admin_password [email]

Ricqchet.Release.bootstrap()
