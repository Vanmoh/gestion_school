from rest_framework import serializers

from .models import ActivityLog


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
