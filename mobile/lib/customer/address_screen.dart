import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'cart.dart';
import 'payment_screen.dart';
import 'shop_widgets.dart';

/// Test spots for local mode, near the stores in config/staff.example.yaml.
const _testLocations = <String, ({double lat, double lng})>{
  'Near Kothrud store': (lat: 18.5100, lng: 73.8077),
  'Near Aundh store': (lat: 18.5560, lng: 73.8077),
  'Mumbai (no store)': (lat: 18.9400, lng: 72.8300),
};

/// FR-U-06 to FR-U-08: one delivery address per order, then the 4 km store check.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _name = TextEditingController();
  final _house = TextEditingController();
  final _street = TextEditingController();
  final _landmark = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  ({double lat, double lng})? _pin;
  String? _pinLabel;
  Map<String, String> _serverErrors = {};
  ({String title, String message, Tone tone})? _problem;
  AutovalidateMode _validate = AutovalidateMode.disabled;
  bool _busy = false;
  bool _locating = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _useLastAddress(Map<String, dynamic> a) {
    setState(() {
      _name.text = a['name'] as String? ?? '';
      _house.text = a['house'] as String? ?? '';
      _street.text = a['street'] as String? ?? '';
      _landmark.text = a['landmark'] as String? ?? '';
      _city.text = a['city'] as String? ?? '';
      _pincode.text = a['pincode'] as String? ?? '';
      if (a['lat'] != null && a['lng'] != null) {
        _pin = (lat: (a['lat'] as num).toDouble(), lng: (a['lng'] as num).toDouble());
        _pinLabel = 'Saved location';
      }
    });
  }

  String? _required(String field, String? value, int min, String label) {
    if (_serverErrors[field] != null) return _serverErrors[field];
    return (value?.trim().length ?? 0) < min ? '$label is required' : null;
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showInfo(context, 'Allow location access to pin your delivery point, or fill in the address below.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _pin = (lat: position.latitude, lng: position.longitude);
        _pinLabel = 'Current location';
        _problem = null;
      });
    } catch (_) {
      if (mounted) showInfo(context, "Couldn't get your location. Please try again or fill in the address.");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Map<String, dynamic> _address() => {
    'name': _name.text.trim(),
    'house': _house.text.trim(),
    'street': _street.text.trim(),
    if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
    'city': _city.text.trim(),
    'pincode': _pincode.text.trim(),
    if (_pin != null) ...{'lat': _pin!.lat, 'lng': _pin!.lng},
  };

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _serverErrors = {};
      _problem = null;
      _validate = AutovalidateMode.onUserInteraction;
    });
    if (!_form.currentState!.validate()) return;

    setState(() => _busy = true);
    final cart = context.read<Cart>();
    final address = _address();
    try {
      final checkout = await context.read<ApiClient>().post(
        '/checkout',
        body: {'items': cart.toRequest(), 'address': address},
      ) as Map<String, dynamic>;
      cart.lastAddress = address;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PaymentScreen(checkout: checkout, address: address)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'NO_STORE_AVAILABLE':
          _showProblem(
            e.message,
            'We deliver only from stores within 4 km by road. Try a different address or pin a more exact location.',
            Tone.error,
          );
        case 'SERVICEABILITY_UNAVAILABLE':
          _showProblem("We couldn't check delivery right now", e.message, Tone.warning);
        case 'INVALID_ADDRESS':
          setState(() => _serverErrors = {for (final f in e.fields) f: 'Please check this field'});
          _form.currentState!.validate();
          if (e.fields.contains('lat') || e.fields.contains('lng')) _showProblem('Location pin', e.message, Tone.warning);
        default:
          showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showProblem(String title, String message, Tone tone) {
    setState(() => _problem = (title: title, message: message, tone: tone));
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = context.read<Cart>().lastAddress;
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery address')),
      body: Form(
        key: _form,
        autovalidateMode: _validate,
        child: ListView(
          controller: _scroll,
          children: [
            const PageBody(padding: EdgeInsets.zero, child: CheckoutSteps(current: 1)),
            PageBody(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (problem != null)
                    InfoBanner(
                      tone: problem.tone,
                      icon: problem.tone == Tone.error ? Icons.wrong_location_rounded : null,
                      title: problem.title,
                      message: problem.message,
                    ),
                  if (last != null && _name.text.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.history_rounded),
                          title: const Text('Use your last address', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${last['house']}, ${last['street']}, ${last['city']} ${last['pincode']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _useLastAddress(last),
                        ),
                      ),
                    ),
                  _locationCard(context),
                  SectionCard(
                    title: 'Address details',
                    icon: Icons.home_outlined,
                    child: Column(
                      children: [
                        _field(_name, 'name', 'Full name', min: 2, icon: Icons.person_outline_rounded,
                            hints: const [AutofillHints.name]),
                        _field(_house, 'house', 'House / flat number', min: 1, icon: Icons.door_front_door_outlined),
                        _field(_street, 'street', 'Street / area', min: 2, icon: Icons.signpost_outlined,
                            hints: const [AutofillHints.streetAddressLine1]),
                        _field(_landmark, 'landmark', 'Landmark (optional)', min: 0, icon: Icons.place_outlined),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(_city, 'city', 'City', min: 2, icon: Icons.location_city_outlined,
                                  hints: const [AutofillHints.addressCity]),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: TextFormField(
                                  controller: _pincode,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  autofillHints: const [AutofillHints.postalCode],
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(labelText: 'Pincode', counterText: '', errorMaxLines: 2),
                                  validator: (v) =>
                                      _serverErrors['pincode'] ??
                                      (RegExp(r'^[1-9]\d{5}$').hasMatch(v ?? '') ? null : 'Enter a valid 6-digit pincode'),
                                  onFieldSubmitted: (_) => _continue(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const HintLine(icon: Icons.local_shipping_outlined, text: 'Free delivery from a store within 4 km'),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: PrimaryButton(
          label: 'Continue to payment',
          icon: Icons.arrow_forward_rounded,
          busy: _busy,
          onPressed: _continue,
        ),
      ),
    );
  }

  Widget _locationCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final pin = _pin;
    return SectionCard(
      title: 'Delivery location',
      icon: Icons.my_location_rounded,
      trailing: pin == null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: colors.infoContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Recommended',
                style: TextStyle(color: colors.onInfoContainer, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pin == null)
            Text(
              'Pin your exact location so we can find the nearest store by road.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colors.successContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: colors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pinLabel ?? 'Location pinned',
                          style: TextStyle(fontWeight: FontWeight.w700, color: colors.onSuccessContainer),
                        ),
                        Text(
                          '${pin.lat.toStringAsFixed(4)}, ${pin.lng.toStringAsFixed(4)}',
                          style: TextStyle(fontSize: 12, color: colors.onSuccessContainer),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove pin',
                    icon: Icon(Icons.close_rounded, color: colors.onSuccessContainer),
                    onPressed: () => setState(() {
                      _pin = null;
                      _pinLabel = null;
                    }),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.gps_fixed_rounded),
            label: Text(_locating ? 'Finding you…' : (pin == null ? 'Use my current location' : 'Update to current location')),
          ),
          if (AppConfig.localMode) ...[
            const SizedBox(height: 12),
            Text('Test locations', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in _testLocations.entries)
                  ChoiceChip(
                    label: Text(entry.key),
                    selected: _pinLabel == entry.key,
                    onSelected: (_) => setState(() {
                      _pin = entry.value;
                      _pinLabel = entry.key;
                      _problem = null;
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    required int min,
    required IconData icon,
    List<String>? hints,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      autofillHints: hints,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), errorMaxLines: 2),
      textCapitalization: TextCapitalization.words,
      validator: (v) => min == 0 ? _serverErrors[key] : _required(key, v, min, label),
    ),
  );
}
