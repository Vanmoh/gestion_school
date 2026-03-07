from celery import shared_task
from django.core.management import call_command


@shared_task
def scheduled_database_backup():
    call_command("backup_db")
