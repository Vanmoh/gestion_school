import json
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.common.models import ActivityLog
from apps.school.models import Payment


class Command(BaseCommand):
    help = (
        "Backfill Payment.received_by for legacy payments that were created before "
        "the cashier assignment was enforced in PaymentViewSet.perform_create()."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Preview matches without updating the database.",
        )
        parser.add_argument(
            "--window-seconds",
            type=int,
            default=180,
            help="Time window around payment creation used to find matching activity logs.",
        )
        parser.add_argument(
            "--fallback-user-id",
            type=int,
            help="User ID to apply for unresolved payments.",
        )
        parser.add_argument(
            "--fallback-username",
            type=str,
            help="Username to apply for unresolved payments.",
        )
        parser.add_argument(
            "--limit",
            type=int,
            help="Only process the N oldest payments with received_by=NULL.",
        )
        parser.add_argument(
            "--list-users",
            action="store_true",
            help="List available users (id, username, role) and exit.",
        )
        parser.add_argument(
            "--fallback-auto",
            action="store_true",
            help=(
                "Auto-select fallback cashier when unique candidate exists "
                "(priority: accountant, director, super_admin)."
            ),
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        window_seconds = max(15, int(options["window_seconds"]))
        fallback_user_id = options.get("fallback_user_id")
        fallback_username = options.get("fallback_username")
        fallback_auto = options.get("fallback_auto", False)
        limit = options.get("limit")

        if options.get("list_users"):
            self._print_users()
            return

        if fallback_user_id and fallback_username:
            raise CommandError(
                "Use either --fallback-user-id or --fallback-username, not both."
            )

        if fallback_auto and (fallback_user_id or fallback_username):
            raise CommandError(
                "Use --fallback-auto alone, or provide --fallback-user-id / --fallback-username."
            )

        fallback_user = self._resolve_fallback_user(
            fallback_user_id=fallback_user_id,
            fallback_username=fallback_username,
            fallback_auto=fallback_auto,
        )

        queryset = Payment.objects.filter(received_by__isnull=True).select_related("fee")
        queryset = queryset.order_by("created_at", "id")
        if limit:
            queryset = queryset[: max(1, int(limit))]

        payments = list(queryset)
        total = len(payments)
        if total == 0:
            self.stdout.write(self.style.SUCCESS("No legacy payments to backfill."))
            return

        stats = {
            "total": total,
            "inferred": 0,
            "fallback": 0,
            "unresolved": 0,
        }

        to_update = []

        for payment in payments:
            inferred_user = self._infer_user_from_logs(
                payment=payment,
                window_seconds=window_seconds,
            )

            if inferred_user is not None:
                stats["inferred"] += 1
                self.stdout.write(
                    f"[MATCH] payment#{payment.id} -> user#{inferred_user.id} "
                    f"({self._display_user(inferred_user)})"
                )
                if not dry_run:
                    payment.received_by = inferred_user
                    to_update.append(payment)
                continue

            if fallback_user is not None:
                stats["fallback"] += 1
                self.stdout.write(
                    f"[FALLBACK] payment#{payment.id} -> user#{fallback_user.id} "
                    f"({self._display_user(fallback_user)})"
                )
                if not dry_run:
                    payment.received_by = fallback_user
                    to_update.append(payment)
                continue

            stats["unresolved"] += 1
            self.stdout.write(f"[UNRESOLVED] payment#{payment.id}")

        if not dry_run and to_update:
            with transaction.atomic():
                Payment.objects.bulk_update(to_update, ["received_by"])

        summary = (
            f"Summary: total={stats['total']} | inferred={stats['inferred']} | "
            f"fallback={stats['fallback']} | unresolved={stats['unresolved']}"
        )
        if dry_run:
            self.stdout.write(self.style.WARNING(f"DRY RUN - {summary}"))
        else:
            self.stdout.write(self.style.SUCCESS(summary))

    def _resolve_fallback_user(
        self,
        fallback_user_id=None,
        fallback_username=None,
        fallback_auto=False,
    ):
        User = get_user_model()

        if fallback_user_id is not None:
            try:
                return User.objects.get(id=fallback_user_id)
            except User.DoesNotExist as exc:
                raise CommandError(
                    f"No user found with id={fallback_user_id}."
                ) from exc

        if fallback_username:
            try:
                return User.objects.get(username=fallback_username)
            except User.DoesNotExist as exc:
                examples = list(
                    User.objects.order_by("id").values_list("username", flat=True)[:12]
                )
                sample = ", ".join(examples) if examples else "<no user>"
                raise CommandError(
                    f"No user found with username='{fallback_username}'. "
                    f"Try --list-users. Sample usernames: {sample}"
                ) from exc

        if fallback_auto:
            for role in ("accountant", "director", "super_admin"):
                role_users = list(User.objects.filter(role=role, is_active=True).order_by("id")[:3])
                if len(role_users) == 1:
                    selected = role_users[0]
                    self.stdout.write(
                        self.style.WARNING(
                            f"[AUTO] Fallback user selected: user#{selected.id} "
                            f"({self._display_user(selected)} | {selected.username} | {selected.role})"
                        )
                    )
                    return selected

            candidates = list(
                User.objects.filter(is_active=True)
                .order_by("id")
                .values_list("id", "username", "role")[:12]
            )
            display = ", ".join(
                [f"#{u[0]}:{u[1]}({u[2]})" for u in candidates]
            )
            raise CommandError(
                "Unable to auto-select a unique fallback user. "
                "Use --fallback-username or --fallback-user-id. "
                f"Candidates: {display or '<none>'}"
            )

        return None

    def _print_users(self):
        User = get_user_model()
        rows = list(
            User.objects.order_by("id").values_list(
                "id", "username", "role", "first_name", "last_name", "is_active"
            )
        )
        self.stdout.write(f"Users: {len(rows)}")
        for row in rows:
            user_id, username, role, first_name, last_name, is_active = row
            full_name = f"{(first_name or '').strip()} {(last_name or '').strip()}".strip()
            status = "active" if is_active else "inactive"
            self.stdout.write(
                f"- #{user_id} | {username} | {role} | {full_name or '-'} | {status}"
            )

    def _infer_user_from_logs(self, payment: Payment, window_seconds: int):
        start = payment.created_at - timedelta(seconds=window_seconds)
        end = payment.created_at + timedelta(seconds=window_seconds)

        logs = (
            ActivityLog.objects.select_related("user")
            .filter(
                method="POST",
                success=True,
                user__isnull=False,
                created_at__gte=start,
                created_at__lte=end,
                module__iexact="payments",
            )
            .order_by("created_at", "id")
        )

        best_user = None
        best_score = -1
        best_time_delta = None

        for log in logs:
            payload = self._parse_payload(log.details)
            score = self._score_log_match(log, payload, payment)
            if score < 55:
                continue

            time_delta = abs((log.created_at - payment.created_at).total_seconds())
            if (
                score > best_score
                or (score == best_score and (best_time_delta is None or time_delta < best_time_delta))
            ):
                best_score = score
                best_time_delta = time_delta
                best_user = log.user

        return best_user

    def _score_log_match(self, log: ActivityLog, payload, payment: Payment) -> int:
        score = 0

        path = (log.path or "").lower()
        if "/payments" in path:
            score += 20

        score += max(0, 20 - int(abs((log.created_at - payment.created_at).total_seconds()) // 15))

        if not payload:
            details = (log.details or "").replace(" ", "")
            if f'"fee":{payment.fee_id}' in details:
                score += 35
            if self._amount_in_string(details, payment.amount):
                score += 20
            return score

        payload_fee = self._as_int(payload.get("fee"))
        if payload_fee == payment.fee_id:
            score += 35

        payload_amount = payload.get("amount")
        if self._same_amount(payload_amount, payment.amount):
            score += 20

        payload_method = (payload.get("method") or "").strip().lower()
        payment_method = (payment.method or "").strip().lower()
        if payload_method and payment_method and payload_method == payment_method:
            score += 10

        payload_reference = (payload.get("reference") or "").strip().lower()
        payment_reference = (payment.reference or "").strip().lower()
        if payload_reference and payment_reference and payload_reference == payment_reference:
            score += 10

        return score

    def _parse_payload(self, details: str):
        text = (details or "").strip()
        if not text or text.lower().startswith("payload masqu"):
            return None
        try:
            data = json.loads(text)
        except Exception:
            return None
        return data if isinstance(data, dict) else None

    def _amount_in_string(self, details_without_spaces: str, payment_amount: Decimal) -> bool:
        amount_text = str(payment_amount)
        amount_plain = format(payment_amount, "f")
        return (
            f'"amount":"{amount_text}"' in details_without_spaces
            or f'"amount":"{amount_plain}"' in details_without_spaces
            or f'"amount":{amount_plain}' in details_without_spaces
        )

    def _same_amount(self, value, expected: Decimal) -> bool:
        try:
            parsed = Decimal(str(value))
        except (InvalidOperation, TypeError, ValueError):
            return False
        return parsed == expected

    def _as_int(self, value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    def _display_user(self, user) -> str:
        full_name = (user.get_full_name() or "").strip()
        return full_name or user.username
