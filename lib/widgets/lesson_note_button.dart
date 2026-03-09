import 'package:flutter/material.dart';
import 'package:lanis/generated/l10n.dart';

import '../core/sph/sph.dart';

/// A compact icon button that lets the user attach a personal note to any
/// lesson entry (identified by [courseID] + [entryID]).
///
/// When a note exists the icon is filled; when empty it's outlined.
/// Tapping opens an edit dialog. Used both inside [HomeworkBox]'s header row
/// and as a standalone widget for entries that have no homework.
class LessonNoteButton extends StatelessWidget {
  final String courseID;
  final String entryID;

  const LessonNoteButton({
    super.key,
    required this.courseID,
    required this.entryID,
  });

  Future<void> _editNote(BuildContext context, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).homeworkNoteTitle),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(ctx).homeworkNoteHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          if (current != null && current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(AppLocalizations.of(ctx).homeworkNoteDelete),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );
    if (saved == null) return;
    if (saved.isEmpty) {
      await sph!.prefs.deleteHomeworkNote(courseID, entryID);
    } else {
      await sph!.prefs.setHomeworkNote(courseID, entryID, saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: sph!.prefs.watchHomeworkNote(courseID, entryID),
      builder: (context, snapshot) {
        final note = snapshot.data;
        final hasNote = note != null && note.isNotEmpty;
        return IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          tooltip: hasNote
              ? AppLocalizations.of(context).homeworkNoteTitle
              : AppLocalizations.of(context).homeworkNoteAdd,
          icon: Icon(
            hasNote ? Icons.note_alt : Icons.note_alt_outlined,
            color: hasNote
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => _editNote(context, note),
        );
      },
    );
  }
}
