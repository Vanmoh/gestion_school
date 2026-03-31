import 'package:flutter/material.dart';

import 'timetable_availability_page.dart';
import 'timetable_page.dart';

class TimetableModulePage extends StatefulWidget {
  const TimetableModulePage({super.key});

  @override
  State<TimetableModulePage> createState() => _TimetableModulePageState();
}

class _TimetableModulePageState extends State<TimetableModulePage> {
  String _section = 'timetable';

  @override
  Widget build(BuildContext context) {
    final sections = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'timetable',
        child: Text('Emploi du temps'),
      ),
      const DropdownMenuItem(
        value: 'availability',
        child: Text('Disponibilite Enseignant'),
      ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.view_list_outlined),
              const SizedBox(width: 10),
              const Text('Section:'),
              const SizedBox(width: 12),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _section,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: sections,
                  onChanged: (value) {
                    if (value == null || value == _section) return;
                    setState(() => _section = value);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _section == 'timetable'
              ? const TimetablePage()
              : const TeacherAvailabilityPage(),
        ),
      ],
    );
  }
}
