import 'package:flutter/material.dart';

import '../core/sph/sph.dart';

/// Displays the note text for a lesson/homework entry as a compact row.
/// Renders nothing when there is no note or the note is empty.
class LessonNoteContent extends StatelessWidget {
  final String courseID;
  final String entryID;

  const LessonNoteContent({
    super.key,
    required this.courseID,
    required this.entryID,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: sph?.prefs.watchHomeworkNote(courseID, entryID),
      builder: (context, snapshot) {
        final note = snapshot.data;
        if (note == null || note.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.note_alt,
                size: 14,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
