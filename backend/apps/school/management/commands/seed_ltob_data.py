import re
import random
import logging
from datetime import date
from decimal import Decimal
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from apps.school.models import Etablissement, AcademicYear, ClassRoom, Subject, Student
from apps.accounts.models import User

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Seed LTOB establishment with classes, subjects, and students using custom matricule format"

    # Malian first names
    MALE_FIRST_NAMES = [
        "Mamadou", "Amadou", "Mohamed", "Karim", "Abdoulaye",
        "Malick", "Boubacar", "Ibrahim", "Ousmane", "Aliou",
        "Mustafa", "Saïd", "Bassam", "Hassan", "Youssouf",
        "Adama", "Souleymane", "Koceila", "Issa", "Daouda"
    ]

    FEMALE_FIRST_NAMES = [
        "Fatoumata", "Aïssatou", "Mariam", "Kadiatou", "Oumou",
        "Niarela", "Hawa", "Aminata", "Maïmouna", "Ndeye",
        "Zainaba", "Salimata", "Kounda", "Mbabaly", "Hadjia",
        "Arame", "Miriam", "Awa", "Ramata", "Safiatou"
    ]

    # Malian family names
    LAST_NAMES = [
        "Coulibaly", "Diarra", "Keita", "Diallo", "Traore",
        "Ba", "Sy", "Cissé", "Sow", "Kone",
        "Doucouré", "Camara", "Bah", "Jallow", "Sidibe",
        "Sarr", "Ndiaye", "Fall", "Thiam", "Gueye"
    ]

    # Class definitions for LTOB
    CLASSES = [
        {"name": "10ème CT", "code": "10CT"},
        {"name": "11ème CG", "code": "11CG"},
        {"name": "11ème GM", "code": "11GM"},
        {"name": "12ème CG", "code": "12CG"},
        {"name": "12ème GM", "code": "12GM"},
    ]

    # Subject definitions per class
    SUBJECTS_BY_CLASS = {
        "10CT": [
            {"name": "Français", "code": "FR", "coefficient": 3},
            {"name": "Anglais", "code": "AN", "coefficient": 2},
            {"name": "Mathématiques", "code": "MA", "coefficient": 4},
            {"name": "Sciences Physiques", "code": "PH", "coefficient": 3},
            {"name": "Sciences Naturelles", "code": "SN", "coefficient": 3},
            {"name": "Géographie", "code": "GE", "coefficient": 2},
            {"name": "Histoire", "code": "HI", "coefficient": 2},
            {"name": "Éducation Civique", "code": "EC", "coefficient": 1},
            {"name": "Informatique", "code": "IN", "coefficient": 2},
        ],
        "11CG": [
            {"name": "Français", "code": "FR", "coefficient": 3},
            {"name": "Anglais", "code": "AN", "coefficient": 2},
            {"name": "Mathématiques", "code": "MA", "coefficient": 4},
            {"name": "Comptabilité", "code": "CO", "coefficient": 4},
            {"name": "Droit Commercial", "code": "DC", "coefficient": 2},
            {"name": "Économie", "code": "EC", "coefficient": 2},
            {"name": "Gestion", "code": "GE", "coefficient": 3},
            {"name": "Informatique", "code": "IN", "coefficient": 2},
            {"name": "Géographie", "code": "GG", "coefficient": 2},
        ],
        "11GM": [
            {"name": "Français", "code": "FR", "coefficient": 3},
            {"name": "Anglais", "code": "AN", "coefficient": 2},
            {"name": "Mathématiques", "code": "MA", "coefficient": 4},
            {"name": "Sciences Mécaniques", "code": "ME", "coefficient": 3},
            {"name": "Dessin Technique", "code": "DT", "coefficient": 3},
            {"name": "Technologie", "code": "TE", "coefficient": 3},
            {"name": "Électricité", "code": "EL", "coefficient": 2},
            {"name": "Informatique", "code": "IN", "coefficient": 2},
            {"name": "Sécurité", "code": "SE", "coefficient": 1},
        ],
        "12CG": [
            {"name": "Français", "code": "FR", "coefficient": 3},
            {"name": "Anglais", "code": "AN", "coefficient": 2},
            {"name": "Mathématiques", "code": "MA", "coefficient": 4},
            {"name": "Comptabilité Approfondie", "code": "CA", "coefficient": 4},
            {"name": "Audit et Contrôle", "code": "AC", "coefficient": 3},
            {"name": "Fiscalité", "code": "FI", "coefficient": 2},
            {"name": "Droit", "code": "DR", "coefficient": 2},
            {"name": "Informatique Avancée", "code": "IA", "coefficient": 2},
            {"name": "Gestion Financière", "code": "GF", "coefficient": 3},
        ],
        "12GM": [
            {"name": "Français", "code": "FR", "coefficient": 3},
            {"name": "Anglais", "code": "AN", "coefficient": 2},
            {"name": "Mathématiques", "code": "MA", "coefficient": 4},
            {"name": "Mécanique Avancée", "code": "MA_ADV", "coefficient": 3},
            {"name": "Systèmes Hydrauliques", "code": "SH", "coefficient": 3},
            {"name": "Électronique", "code": "ET", "coefficient": 2},
            {"name": "Automatisation", "code": "AU", "coefficient": 3},
            {"name": "CAO - Conception", "code": "CAO", "coefficient": 2},
            {"name": "Qualité et Maintenance", "code": "QM", "coefficient": 2},
        ],
    }

    def generate_malian_name(self, gender=None):
        """Generate a random Malian name"""
        if gender is None:
            gender = random.choice(['M', 'F'])

        if gender == 'F':
            first_name = random.choice(self.FEMALE_FIRST_NAMES)
        else:
            first_name = random.choice(self.MALE_FIRST_NAMES)

        last_name = random.choice(self.LAST_NAMES)
        return f"{first_name} {last_name}", gender

    def generate_valid_birthdate(self, year_min=2005, year_max=2007):
        """Generate a valid birthdate avoiding edge cases like Feb 30th"""
        year = random.randint(year_min, year_max)
        month = random.randint(1, 12)

        # Days per month (handling leap years for Feb)
        days_in_month = {
            1: 31, 2: 29 if year % 4 == 0 else 28, 3: 31, 4: 30, 5: 31, 6: 30,
            7: 31, 8: 31, 9: 30, 10: 31, 11: 30, 12: 31
        }

        max_day = days_in_month.get(month, 28)
        day = random.randint(1, max_day)

        return date(year, month, day)

    def generate_etablissement_code(self, name):
        """Generate 2-letter establishment code from name (e.g. 'LTOB' -> 'LT')"""
        normalized = re.findall(r"[A-Z0-9]+", name.upper())
        if len(normalized) >= 2:
            return "".join(part[0] for part in normalized[:2])
        if normalized:
            return normalized[0][:2]
        return "GS"

    def generate_custom_matricule(self, etablissement_code, class_code, entry_year, sequence, gender):
        """
        Generate custom matricule in format: RC15CG23E1485F
        RC = establishment code
        15 = etablissement code suffix or derived code
        CG = class code (from class)
        23 = entry year
        E = entry type (E for entry)
        1485 = sequence (padded with zeros)
        F/M = gender indicator
        """
        gender_indicator = 'F' if gender == 'F' else 'M'
        entry_year_code = str(entry_year)[-2:]
        return f"{etablissement_code}{class_code}{entry_year_code}E{sequence:04d}{gender_indicator}"

    def add_arguments(self, parser):
        parser.add_argument(
            '--etablissement',
            type=str,
            default='LTOB',
            help='Etablissement name (default: LTOB)'
        )
        parser.add_argument(
            '--academic-year',
            type=str,
            default='2024-2025',
            help='Academic year (default: 2024-2025)'
        )

    def handle(self, *args, **options):
        etab_name = options['etablissement']
        academic_year_str = options['academic_year']

        try:
            logger.info(f"Starting LTOB seed for {etab_name} ({academic_year_str})")

            # Get or create etablissement
            etablissement, created = Etablissement.objects.get_or_create(
                name=etab_name,
                defaults={
                    'address': f'{etab_name}, Mali',
                    'phone': '+223 12 34 56 78',
                    'email': f'contact@{etab_name.lower().replace(" ", "_")}.ml'
                }
            )
            if created:
                self.stdout.write(self.style.SUCCESS(f'Created etablissement: {etablissement.name}'))
                logger.info(f"Created etablissement: {etablissement.id}")
            else:
                self.stdout.write(f'Using existing etablissement: {etablissement.name}')
                logger.info(f"Using existing etablissement: {etablissement.id}")

            # Get or create academic year
            try:
                academic_year = AcademicYear.objects.get(name=academic_year_str)
            except AcademicYear.DoesNotExist:
                raise CommandError(f'Academic year "{academic_year_str}" not found. Please create it first.')

            self.stdout.write(f'Using academic year: {academic_year.name}')
            logger.info(f"Using academic year: {academic_year.id}")
            etablissement_code = self.generate_etablissement_code(etablissement.name)

            # Create classes
            classrooms_created = []
            for class_info in self.CLASSES:
                classroom, created = ClassRoom.objects.get_or_create(
                    name=class_info["name"],
                    academic_year=academic_year,
                    etablissement=etablissement,
                    defaults={}
                )
                classrooms_created.append(classroom)
                if created:
                    self.stdout.write(self.style.SUCCESS(f'  ✓ Created classroom: {classroom.name}'))
                else:
                    self.stdout.write(f'  ⚙ Using existing classroom: {classroom.name}')

            self.stdout.write(self.style.SUCCESS(f'\n✓ Total classrooms: {len(classrooms_created)}'))

            # Create subjects
            subjects_created = 0
            for classroom in classrooms_created:
                class_code = next(
                    (c["code"] for c in self.CLASSES if c["name"] == classroom.name),
                    None
                )
                
                if class_code and class_code in self.SUBJECTS_BY_CLASS:
                    for subject_info in self.SUBJECTS_BY_CLASS[class_code]:
                        subject, created = Subject.objects.get_or_create(
                            name=subject_info["name"],
                            code=subject_info["code"],
                            classroom=classroom,
                            defaults={'coefficient': Decimal(str(subject_info["coefficient"]))}
                        )
                        if created:
                            subjects_created += 1
                            self.stdout.write(f'  ✓ Created: {subject.code} - {subject.name}')

            self.stdout.write(self.style.SUCCESS(f'\n✓ Total subjects created: {subjects_created}'))

            # Create students
            students_created = 0
            students_per_class = 10
            sequence_counter = 1

            for classroom in classrooms_created:
                class_code = next(
                    (c["code"] for c in self.CLASSES if c["name"] == classroom.name),
                    None
                )

                for i in range(students_per_class):
                    name, gender = self.generate_malian_name()
                    name_parts = name.split()
                    first_name = name_parts[0]
                    last_name = name_parts[1] if len(name_parts) > 1 else ''

                    # Create or update user
                    username = f"student_{classroom.id}_{i}_{sequence_counter}"
                    user, user_created = User.objects.get_or_create(
                        username=username,
                        defaults={
                            'email': f'{username}@ltob.school',
                            'first_name': first_name,
                            'last_name': last_name,
                            'is_active': True,
                        }
                    )

                    # Create student profile
                    student, student_created = Student.objects.get_or_create(
                        user=user,
                        defaults={
                            'gender': gender,
                            'classroom': classroom,
                            'etablissement': etablissement,
                            'birth_date': self.generate_valid_birthdate(),
                            'conduite': Decimal(random.randint(15, 20)),
                        }
                    )

                    if student_created:
                        students_created += 1
                        self.stdout.write(
                            f'  ✓ Created: {student.matricule} - {student.user.get_full_name()} ({classroom.name})'
                        )
                    
                    sequence_counter += 1

            self.stdout.write(self.style.SUCCESS(f'\n✓ Total students created: {students_created}'))

            # Summary
            self.stdout.write(self.style.SUCCESS('\n' + '='*60))
            self.stdout.write(self.style.SUCCESS('SEEDING COMPLETED SUCCESSFULLY'))
            self.stdout.write(self.style.SUCCESS('='*60))
            self.stdout.write(f'Établissement: {etablissement.name}')
            self.stdout.write(f'Année académique: {academic_year.name}')
            self.stdout.write(f'Classes: {len(classrooms_created)}')
            self.stdout.write(f'Matières: {subjects_created}')
            self.stdout.write(f'Élèves: {students_created}')
            self.stdout.write(self.style.SUCCESS('='*60 + '\n'))

        except Exception as e:
            raise CommandError(f'Error during seeding: {str(e)}')
