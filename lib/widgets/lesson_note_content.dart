import 'package:flutter/material.dart';
import 'package:lanis/generated/l10n.dart';
import 'package:lanis/widgets/format_text.dart';

import '../core/sph/sph.dart';

/// Displays the note text for a lesson/homework entry as a compact row.
/// Renders nothing when there is no note or the note is empty.
class LessonNoteBox extends StatelessWidget {
  final String courseID;
  final String entryID;

  const LessonNoteBox({
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
        return Container(
          padding: EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.note_alt,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context).note,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.2),
                        Theme.of(context).cardColor,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.only(
                      left: 12.0,
                      right: 12.0,
                      top: 8.0,
                      bottom: 8.0,
                    ),
                    child: FormattedText(
                      text: note,
                      formatStyle: DefaultFormatStyle(context: context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
