# 1121citrus/pg-volume-backup

Back up Docker volumes and PostgreSQL databases to S3.

## Synopsis

`pg-volume-backup` backs up named Docker volumes and PostgreSQL databases to
an S3 bucket on a configurable schedule.  Each volume produces its own
timestamped archive, optionally compressed and GPG-encrypted.  A SHA-256
checksum companion file is created alongside each archive for integrity
verification.

Designed to work alongside
[1121citrus/rotate-aws-backups](https://github.com/1121citrus/rotate-aws-backups)
for retention management.

