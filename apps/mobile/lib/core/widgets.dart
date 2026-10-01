import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'approvals.dart';
import 'formatters.dart';
import 'platform.dart';
import 'supabase_providers.dart';
import 'theme.dart';
import 'walkthrough.dart';

/// Filled buttons in dialog actions: sized to their label, so they sit
/// beside Cancel. (The phone theme makes filled buttons full width, which
/// pushed them onto their own line under Cancel.)
final dialogActionStyle = FilledButton.styleFrom(
  minimumSize: const Size(88, 44),
);

/// True when the window is wide enough for the desktop layout (sidebar,
/// tables, header buttons).
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

/// A screen's main action ("Add product", "New bill"). On a phone it is the
/// floating button; on desktop it is a button at the end of the app bar,
/// where desktop software keeps it. Use [fab] for the Scaffold's
/// floatingActionButton and put [inAppBar] last in the app bar's actions.
class ScreenAction {
  const ScreenAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.coachPage,
    this.coachId,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// The walkthrough step that points at this action, if any.
  final String? coachPage;
  final String? coachId;

  Widget _coach(Widget child) => coachPage == null || coachId == null
      ? child
      : CoachTarget(page: coachPage!, id: coachId!, child: child);

  Widget? fab(BuildContext context) => isWideLayout(context)
      ? null
      : _coach(
          FloatingActionButton.extended(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          ),
        );

  Widget inAppBar(BuildContext context) => !isWideLayout(context)
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(left: 8, right: 16),
          child: _coach(
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
          ),
        );
}

/// Explicit AppBar back button for screens living under the secondary
/// ShellRoute (invoices, customers, purchases, …). Those pages sit in the
/// shell's own inner Navigator, where each is the only page in the stack —
/// so AppBar's automatic back arrow (which asks the *nearest* Navigator
/// "can you pop?") never appears, even though GoRouter can pop back across
/// navigators just fine. Returns null when there's genuinely nowhere to go
/// back to (e.g. the screen is the app's initial location), so AppBar
/// falls back to showing nothing.
Widget? appBarBack(BuildContext context) => GoRouter.of(context).canPop()
    ? BackButton(onPressed: () => context.pop())
    : null;

/// Colored initials avatar (deterministic color per name) — used for
/// customers, suppliers and invoice lists.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.radius = 21, this.icon});

  final String name;
  final double radius;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final color = AppColors.accentFor(trimmed.isEmpty ? '?' : trimmed);
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.characters.first.toUpperCase()
        : (parts.first.characters.first + parts[1].characters.first)
              .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      child: trimmed.isEmpty && icon != null
          ? Icon(icon, color: color, size: radius)
          : Text(
              initials,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.72,
              ),
            ),
    );
  }
}

/// Pastel icon chip used on stat cards and list tiles.
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// Standard loading / error / data handling for AsyncValue.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(friendlyError(e), textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.hint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return 'No internet connection. Please check your network.';
  }
  // Owner approval needed (migration 0044) — the message carries a JSON list.
  final approval = approvalExceptions(e);
  if (approval != null) {
    return approval.isEmpty
        ? 'This sale needs the owner\'s approval.'
        : 'Needs the owner\'s approval — ${approvalSummary(approval)}';
  }
  // Surface PostgREST / RPC exception messages cleanly
  final match = RegExp(r'message:? ?([^,}]+)').firstMatch(s);
  return match?.group(1)?.trim() ?? s;
}

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  final text = friendlyError(e);
  if (text.contains('subscription has expired or is suspended') ||
      text.contains('is not included in your plan') ||
      text.contains('Staff limit')) {
    try {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(appContextProvider.notifier).refreshSilently();
    } catch (_) {}
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(friendlyError(e)),
      backgroundColor: Colors.red.shade700,
    ),
  );
}

void showSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: dialogActionStyle,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Manual barcode/serial entry dialog — the desktop fallback for screens
/// that otherwise push the camera-based `/scan` route (mobile_scanner has
/// no Windows/Linux backend, so desktop builds type the code instead).
Future<String?> promptBarcode(
  BuildContext context, {
  String title = 'Enter code',
}) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Barcode / serial number'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: dialogActionStyle,
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Use code'),
        ),
      ],
    ),
  );
  return code?.trim().isEmpty ?? true ? null : code!.trim();
}

/// Section label used in forms.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: AppColors.inkSoft),
    ),
  );
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.controller,
    this.autofocus = false,
    this.suffix,
    this.focusNode,
    this.onSubmitted,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;
  final bool autofocus;
  final Widget? suffix;
  final FocusNode? focusNode;

  /// Fired on Enter — external keyboard-wedge barcode scanners end
  /// every scan with an Enter keypress.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: onSubmitted != null ? TextInputAction.search : null,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Small colored status chip (paid / partial / unpaid, etc).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  Color get _color {
    if (color != null) return color!;
    switch (label.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'unpaid':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

/// A sortable column for [DesktopTable]. Pass [comparable] to make the
/// column clickable-to-sort; omit it for a plain, unsortable header (e.g. a
/// trailing "Status" column).
class DesktopTableColumn<T> {
  const DesktopTableColumn({
    required this.label,
    required this.flex,
    this.alignEnd = false,
    this.comparable,
  });

  final String label;
  final int flex;
  final bool alignEnd;
  final Comparable Function(T row)? comparable;
}

/// Reusable "real desktop app" table shell: a bordered white card with a
/// clickable/sortable header row over dense, divided data rows — used in
/// place of the mobile card list once a screen is wide enough to read as
/// desktop software (reference: Vyapar Desktop's item/transaction tables)
/// rather than a phone list stretched wide. Sort state is local to the
/// widget; each screen only supplies its columns and a row builder.
class DesktopTable<T> extends StatefulWidget {
  const DesktopTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.rowBuilder,
    this.leadingWidth = 54,
    this.trailingWidth,
    this.initialSortIndex = 0,
    this.initialAscending = true,
  });

  final List<T> rows;
  final List<DesktopTableColumn<T>> columns;
  final Widget Function(BuildContext context, T row) rowBuilder;

  /// Reserved space at the start of each row/header for a leading icon.
  final double leadingWidth;

  /// Reserved space at the end of each row/header (e.g. a status chip) that
  /// isn't one of [columns] — pass null if rows have no trailing element.
  final double? trailingWidth;
  final int initialSortIndex;
  final bool initialAscending;

  @override
  State<DesktopTable<T>> createState() => _DesktopTableState<T>();
}

class _DesktopTableState<T> extends State<DesktopTable<T>> {
  late int _sortIndex = widget.initialSortIndex;
  late bool _ascending = widget.initialAscending;

  List<T> get _sortedRows {
    final comparable = widget.columns[_sortIndex].comparable;
    if (comparable == null) return widget.rows;
    final sorted = List<T>.from(widget.rows);
    sorted.sort((a, b) {
      final cmp = comparable(a).compareTo(comparable(b));
      return _ascending ? cmp : -cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final sortedRows = _sortedRows;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView.separated(
                    itemCount: sortedRows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: AppColors.line),
                    itemBuilder: (context, i) =>
                        widget.rowBuilder(context, sortedRows[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: widget.leadingWidth),
          for (var i = 0; i < widget.columns.length; i++) _headerCell(i),
          if (widget.trailingWidth != null)
            SizedBox(width: widget.trailingWidth),
        ],
      ),
    );
  }

  Widget _headerCell(int i) {
    final col = widget.columns[i];
    final active = _sortIndex == i;
    final sortable = col.comparable != null;
    final content = Row(
      mainAxisAlignment: col.alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Text(
          col.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.primary : AppColors.inkSoft,
          ),
        ),
        if (sortable) ...[
          const SizedBox(width: 3),
          Icon(
            active
                ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 14,
            color: active
                ? AppColors.primary
                : AppColors.inkSoft.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
    return Expanded(
      flex: col.flex,
      child: sortable
          ? InkWell(
              onTap: () => setState(() {
                if (_sortIndex == i) {
                  _ascending = !_ascending;
                } else {
                  _sortIndex = i;
                  _ascending = true;
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: content,
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: content,
            ),
    );
  }
}

/// A ₹/% mode toggle paired with a numeric field — used for discount entry
/// on POS lines/bills and purchase bills. The caller owns the raw entered
/// number and the mode (so switching modes never loses what was typed);
/// this widget only renders the input and reports changes.
class AmountOrPercentField extends StatelessWidget {
  const AmountOrPercentField({
    super.key,
    required this.controller,
    required this.isPercent,
    required this.onModeChanged,
    this.onChanged,
    this.label,
  });

  final TextEditingController controller;
  final bool isPercent;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<String>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              prefixText: isPercent ? null : '₹ ',
              suffixText: isPercent ? '%' : null,
              hintText: '0',
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('₹')),
            ButtonSegment(value: true, label: Text('%')),
          ],
          selected: {isPercent},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
      ],
    );
  }
}

/// Lays cards out in a responsive multi-column wrap. Unlike a `GridView`
/// with a forced aspect ratio, each card keeps its own natural height —
/// important for cards like [PartyCard] that show a variable number of
/// optional rows (credit limit, over-limit warning, pay button).
Widget responsiveCardWrap(
  List<Widget> cards, {
  double minCardWidth = 300,
  int maxColumns = 4,
  double spacing = 12,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / minCardWidth).floor().clamp(
        1,
        maxColumns,
      );
      final cardWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in cards) SizedBox(width: cardWidth, child: c)],
      );
    },
  );
}

/// Rich contact-style card for a customer/supplier — the desktop grid
/// alternative to a plain [DesktopTable] row. Surfaces due amount and
/// credit-limit context at a glance, plus one-tap quick actions (call,
/// record payment) that previously only existed on the detail screen.
class PartyCard extends StatelessWidget {
  const PartyCard({
    super.key,
    required this.name,
    required this.phone,
    required this.due,
    required this.dueLabel,
    required this.dueColor,
    this.creditLimit,
    this.overLimit = false,
    required this.onTap,
    this.onCall,
    this.onPay,
    this.payLabel = 'Record payment',
  });

  final String name;
  final String phone;
  final double due;
  final String dueLabel;
  final Color dueColor;
  final double? creditLimit;
  final bool overLimit;
  final VoidCallback onTap;
  final VoidCallback? onCall;
  final VoidCallback? onPay;
  final String payLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  InitialsAvatar(name, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onCall != null && phone.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.call_outlined, size: 19),
                      color: AppColors.teal,
                      tooltip: 'Call $phone',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCall,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dueLabel,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                  Text(
                    money(due),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: due > 0 ? dueColor : AppColors.green,
                    ),
                  ),
                ],
              ),
              if (creditLimit != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Credit limit',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    Text(
                      money(creditLimit),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ],
              if (overLimit) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: AppColors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Over limit by ${money(due - creditLimit!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (onPay != null && due > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: Text(
                      payLabel,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
