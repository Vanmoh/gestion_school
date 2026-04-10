from rest_framework import serializers

from .models import ActivityLog, BackupArchive


class ActivityLogSerializer(serializers.ModelSerializer):
    user_display = serializers.SerializerMethodField(read_only=True)

    def get_user_display(self, obj):
        if not obj.user:
            return "Anonyme"
        full_name = obj.user.get_full_name().strip()
        return full_name or obj.user.username

    class Meta:
        model = ActivityLog
        fields = "__all__"


class BackupArchiveSerializer(serializers.ModelSerializer):
    created_by_display = serializers.SerializerMethodField(read_only=True)
    restored_by_display = serializers.SerializerMethodField(read_only=True)
    etablissement_name = serializers.SerializerMethodField(read_only=True)

    def get_created_by_display(self, obj):
        user = obj.created_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_restored_by_display(self, obj):
        user = obj.restored_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_etablissement_name(self, obj):
        etablissement = obj.etablissement
        return etablissement.name if etablissement else ""

    class Meta:
        model = BackupArchive
        fields = "__all__"
