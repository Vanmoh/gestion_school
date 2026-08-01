from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import serializers

from apps.accounts.models import UserRole
from apps.school.models import ClassRoom, Etablissement, ParentProfile, Student

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
    classroom = serializers.PrimaryKeyRelatedField(
        queryset=ClassRoom.objects.select_related("etablissement").all(),
        required=False,
        allow_null=True,
        write_only=True,
    )
    students = serializers.ListField(
        child=serializers.IntegerField(min_value=1),
        required=False,
        allow_empty=True,
        write_only=True,
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
            "classroom",
            "students",
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

        role = attrs.get("role")
        classroom = attrs.get("classroom")
        student_ids = [int(value) for value in attrs.get("students", [])]

        effective_etablissement = attrs.get("etablissement") or target_etablissement
        if role in {UserRole.STUDENT, UserRole.PARENT} and effective_etablissement is None:
            raise serializers.ValidationError({"etablissement": "Selectionnez un etablissement actif."})

        if role == UserRole.STUDENT:
            if classroom is None:
                raise serializers.ValidationError({"classroom": "La classe est obligatoire pour un eleve."})
            classroom_etab_id = getattr(classroom, "etablissement_id", None)
            target_etab_id = getattr(effective_etablissement, "id", None)
            if target_etab_id is not None and classroom_etab_id != target_etab_id:
                raise serializers.ValidationError(
                    {"classroom": "La classe selectionnee n'appartient pas a l'etablissement actif."}
                )

        elif role == UserRole.PARENT:
            if classroom is None:
                raise serializers.ValidationError({"classroom": "La classe est obligatoire pour un parent."})
            if not student_ids:
                raise serializers.ValidationError({"students": "Selectionnez au moins un eleve."})

            classroom_etab_id = getattr(classroom, "etablissement_id", None)
            target_etab_id = getattr(effective_etablissement, "id", None)
            if target_etab_id is not None and classroom_etab_id != target_etab_id:
                raise serializers.ValidationError(
                    {"classroom": "La classe selectionnee n'appartient pas a l'etablissement actif."}
                )

            students = list(
                Student.objects.select_related("classroom", "etablissement", "user")
                .filter(id__in=student_ids, is_archived=False)
                .order_by("id")
            )
            if len(students) != len(set(student_ids)):
                raise serializers.ValidationError({"students": "Certains eleves selectionnes sont introuvables."})

            if target_etab_id is not None:
                for student in students:
                    student_etab_id = student.etablissement_id or getattr(
                        getattr(student, "classroom", None), "etablissement_id", None
                    )
                    if student_etab_id != target_etab_id:
                        raise serializers.ValidationError(
                            {"students": "Certains eleves n'appartiennent pas a l'etablissement actif."}
                        )

            attrs["resolved_students"] = students

        return attrs

    @transaction.atomic
    def create(self, validated_data):
        password = validated_data.pop("password")
        classroom = validated_data.pop("classroom", None)
        validated_data.pop("students", None)
        resolved_students = validated_data.pop("resolved_students", [])

        user = User(**validated_data)
        user.set_password(password)
        user.save()

        if user.role == UserRole.STUDENT:
            Student.objects.update_or_create(
                user=user,
                defaults={
                    "classroom": classroom,
                    "etablissement": user.etablissement or getattr(classroom, "etablissement", None),
                },
            )

        elif user.role == UserRole.PARENT:
            parent_profile, _ = ParentProfile.objects.get_or_create(
                user=user,
                defaults={"etablissement": user.etablissement},
            )
            if parent_profile.etablissement_id != user.etablissement_id:
                parent_profile.etablissement = user.etablissement
                parent_profile.save(update_fields=["etablissement", "updated_at"])

            for student in resolved_students:
                if student.parent_id != parent_profile.id:
                    student.parent = parent_profile
                    student.save(update_fields=["parent", "updated_at"])

        return user
