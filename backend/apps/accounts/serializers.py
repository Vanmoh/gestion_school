from django.contrib.auth import get_user_model
from rest_framework import serializers

from apps.school.models import Etablissement

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(
        queryset=Etablissement.objects.all(),
        required=False,
        allow_null=True,
    )
    etablissement_name = serializers.CharField(source="etablissement.name", read_only=True)

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "first_name",
            "last_name",
            "email",
            "role",
            "phone",
            "profile_photo",
            "etablissement",
            "etablissement_name",
        ]


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    etablissement = serializers.PrimaryKeyRelatedField(
        queryset=Etablissement.objects.all(),
        required=False,
        allow_null=True,
    )

    class Meta:
        model = User
        fields = [
            "username",
            "first_name",
            "last_name",
            "email",
            "password",
            "role",
            "phone",
            "etablissement",
        ]

    def validate(self, attrs):
        request = self.context.get("request")
        target_etablissement = self.context.get("target_etablissement")

        if request is None:
            return attrs

        requester = request.user
        is_super_admin = getattr(requester, "role", None) == "super_admin"

        if not is_super_admin:
            attrs["etablissement"] = getattr(requester, "etablissement", None)
        elif "etablissement" not in attrs:
            attrs["etablissement"] = target_etablissement

        return attrs

    def create(self, validated_data):
        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user
