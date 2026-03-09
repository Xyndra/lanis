import 'package:flutter/material.dart';
import 'package:lanis/generated/l10n.dart';

import '../../../core/sph/sph.dart';
import '../../../models/lessons.dart';
import '../../../widgets/format_text.dart';

class HomeworkBox extends StatefulWidget {
  final CurrentEntry currentEntry;
  final String courseID;
  final VoidCallback? onTap;
  const HomeworkBox({
    super.key,
    required this.currentEntry,
    required this.courseID,
    this.onTap,
  });

  @override
  State<HomeworkBox> createState() => _HomeworkBoxState();
}

class _HomeworkBoxState extends State<HomeworkBox> with WidgetsBindingObserver {
  final GlobalKey _columnKey = GlobalKey();
  Size _columnSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateColumnSize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateColumnSize();
  }

  void _updateColumnSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Checks if the context is still available to prevent _TypeError
      if (_columnKey.currentContext != null) {
        final RenderBox renderBox =
            _columnKey.currentContext!.findRenderObject() as RenderBox;
        setState(() {
          _columnSize = renderBox.size;
        });
      }
    });
  }

  Future<void> _editNote(String? currentNote) async {
    final controller = TextEditingController(text: currentNote ?? '');
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
          if (currentNote != null && currentNote.isNotEmpty)
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
    if (saved == null || !mounted) return;
    if (saved.isEmpty) {
      await sph!.prefs.deleteHomeworkNote(
        widget.courseID,
        widget.currentEntry.entryID,
      );
    } else {
      await sph!.prefs.setHomeworkNote(
        widget.courseID,
        widget.currentEntry.entryID,
        saved,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: _columnSize.height == 0 ? 0 : _columnSize.height + 12,
              width: _columnSize.width,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
            ),
          ],
        ),
        Column(
          children: [
            Row(
              key: _columnKey,
              children: [
                const SizedBox(width: 8),
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.task,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context).homework,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: widget.currentEntry.homework!.homeWorkDone,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.onPrimary,
                    width: 2,
                  ),
                  onChanged: (bool? value) {
                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context).homeworkSaving,
                          ),
                          duration: const Duration(milliseconds: 500),
                        ),
                      );
                      sph!.parser.lessonsStudentParser
                          .setHomework(
                            widget.courseID,
                            widget.currentEntry.entryID,
                            value!,
                          )
                          .then((val) {
                            if (val != "1") {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).homeworkSavingError,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              setState(() {
                                widget.currentEntry.homework!.homeWorkDone =
                                    value;
                              });
                            }
                          });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context).homeworkSavingError,
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
                    text: widget.currentEntry.homework!.description,
                    formatStyle: DefaultFormatStyle(context: context),
                  ),
                ),
                // On desktop, SelectionArea inside FormattedText intercepts taps for
                // text cursor placement, preventing ListTile.onTap from firing.
                if (widget.onTap != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: widget.onTap,
                    ),
                  ),
              ],
            ),
            // Custom note section — streamed from DB
            StreamBuilder<String?>(
              stream: sph!.prefs.watchHomeworkNote(
                widget.courseID,
                widget.currentEntry.entryID,
              ),
              builder: (context, snapshot) {
                final note = snapshot.data;
                return GestureDetector(
                  onTap: () => _editNote(note),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.12),
                        Theme.of(context).cardColor,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          note != null && note.isNotEmpty
                              ? Icons.edit_note
                              : Icons.note_add_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: note != null && note.isNotEmpty
                              ? Text(
                                  note,
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : Text(
                                  AppLocalizations.of(context).homeworkNoteAdd,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
