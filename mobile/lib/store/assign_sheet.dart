import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Opens the assign sheet for [orderId]. Resolves true when the order was dispatched.
Future<bool> showAssignSheet(BuildContext context, {required String orderId, required String displayOrderId}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AssignSheet(orderId: orderId, displayOrderId: displayOrderId),
  );
  return result == true;
}

/// FR-S-05, A8: pick a delivery boy of this store; confirming also sets "On the way for delivery".
/// Pops true when the order was dispatched.
class AssignSheet extends StatefulWidget {
  const AssignSheet({super.key, required this.orderId, this.displayOrderId});

  final String orderId;
  final String? displayOrderId;

  @override
  State<AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<AssignSheet> {
  // One key per sheet: a double tap or network retry is safe (NFR-11).
  final _idempotencyKey = const Uuid().v4();
  List<Map<String, dynamic>>? _boys;
  Object? _error;
  String? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await context.read<ApiClient>().get('/store/delivery-boys');
      if (mounted) setState(() => _boys = (res['items'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/store/orders/${widget.orderId}/dispatch',
        body: {'deliveryBoyId': _selected},
        headers: {'idempotency-key': _idempotencyKey},
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showError(context, e);
      // EX-18: someone else already changed the order; close and show the latest status.
      if (e.code == 'ORDER_STATE_CHANGED') Navigator.of(context).pop(false);
      if (e.code == 'DELIVERY_BOY_INACTIVE') {
        setState(() => _selected = null);
        _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final boys = _boys;
    final leastBusy = boys == null || boys.length < 2
        ? null
        : boys.map((b) => b['activeOrders'] as int).reduce((a, b) => a < b ? a : b);
    final selectedName = boys?.where((b) => b['id'] == _selected).firstOrNull?['name'] as String?;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assign delivery boy', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.displayOrderId != null ? '${widget.displayOrderId} will be' : 'The order will be'} '
              'marked "On the way for delivery".',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              SizedBox(height: 260, child: ErrorView(error: _error!, onRetry: _load))
            else if (boys == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (boys.isEmpty)
              const InfoBanner(
                tone: Tone.warning,
                title: 'No delivery boys set up',
                message: 'No delivery boys are set up for your store. Please contact support.',
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: boys.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final b = boys[i];
                    return _BoyTile(
                      boy: b,
                      selected: _selected == b['id'],
                      leastBusy: leastBusy != null && b['activeOrders'] == leastBusy,
                      onTap: _busy ? null : () => setState(() => _selected = b['id'] as String),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Confirm – Send for delivery',
              icon: Icons.delivery_dining_rounded,
              busy: _busy,
              onPressed: _selected == null ? null : _confirm,
            ),
            if (selectedName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$selectedName will see this order in their app right away.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoyTile extends StatelessWidget {
  const _BoyTile({required this.boy, required this.selected, required this.leastBusy, required this.onTap});

  final Map<String, dynamic> boy;
  final bool selected;
  final bool leastBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final active = boy['activeOrders'] as int;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.6) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                InitialsAvatar(boy['name'] as String),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              boy['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (leastBusy) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: colors.infoContainer, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                'Least busy',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: colors.onInfoContainer),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(mobileDisplay(boy['mobile'] as String), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active == 0 ? colors.successContainer : colors.warningContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    active == 0 ? 'Free' : '$active on the way',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active == 0 ? colors.onSuccessContainer : colors.onWarningContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
