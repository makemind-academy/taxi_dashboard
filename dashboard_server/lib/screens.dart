/// Two screens off one dashboard: the driver's and the passenger's.
///
/// They are not the same information cropped differently. The driver needs the
/// fare and the state of the trip and nothing that takes eyes off the road; the
/// passenger needs to see what they are being charged and, at the end, how to
/// pay. Serving them as two routes of one app is what lets each stay that
/// short — and what lets the cab's colours be declared once.
library;

/// Colours by role, never by hex, so the two screens cannot drift apart.
const _ink = '{{theme.color.onSurface}}';
const _muted = '{{theme.color.onSurfaceVariant}}';
const _accent = '{{theme.color.primary}}';
const _hair = '{{theme.color.outline}}';
const _surface = '{{theme.color.surface}}';
const _canvas = '{{theme.color.surfaceContainerHighest}}';
const _paid = '{{theme.color.primaryContainer}}';
const _onPaid = '{{theme.color.onPrimaryContainer}}';

/// Money, distance and time are set in a fixed-width face: a fare that grows
/// while the passenger watches must not shift the layout under it.
const _mono = 'JetBrainsMono';

/// A cab at night. The dashboard is lit against a dark cabin, and both screens
/// take that from here rather than each deciding for itself.
const Map<String, dynamic> _cabTheme = {
  'mode': 'dark',
  'color': {
    'primary': '#f0b93f',
    'onPrimary': '#241a05',
    'primaryContainer': '#2f7d5c',
    'onPrimaryContainer': '#eafaf1',
    'surface': '#161d24',
    'onSurface': '#eef3f7',
    'surfaceContainerHighest': '#0d1319',
    'onSurfaceVariant': '#93a3b0',
    'outline': '#26313b',
    'outlineVariant': '#1b242c',
    'error': '#e2685c',
    'onError': '#2a0b08',
    'warning': '#e0a33c',
    'onWarning': '#241a05',
    'inverseSurface': '#eef3f7',
    'inverseOnSurface': '#161d24',
  },
  'spacing': {
    'xxs': 2, 'xs': 4, 'sm': 8, 'md': 16, 'lg': 24, 'xl': 32, '2xl': 48,
  },
  'shape': {
    'none': 0, 'extraSmall': 4, 'small': 8, 'medium': 12, 'large': 16,
    'extraLarge': 28, 'full': 999,
  },
  'fonts': {
    'JetBrainsMono': {'source': 'asset', 'family': 'JetBrainsMono'},
  },
};

const Map<String, dynamic> _initialState = {
  'status': 'Waiting for fare',
  'plate': '',
  'fareLabel': '0',
  'flagfallLabel': '0',
  'distanceChargeLabel': '0',
  'waitingChargeLabel': '0',
  'distanceLabel': '0.00 km',
  'waitingLabel': '0.0 s',
  'kphLabel': '0.0 km/h',
  'framesUsed': 0,
  'meterRule': '',
  'approval': '-',
  'notice': '',
  'payDue': false,
};

/// One app, two routes. The cab is one vehicle; the screens are where you sit.
const Map<String, dynamic> applicationDefinition = {
  'type': 'application',
  'version': '1.3',
  'id': 'city.taxi.dashboard',
  'title': 'Taxi — dashboard and trip',
  'description': 'One meter, seen from the front seat and from the back.',
  'theme': _cabTheme,
  'initialRoute': '/driver',
  'routes': {
    '/driver': 'ui://pages/driver',
    '/passenger': 'ui://pages/passenger',
  },
  'navigation': {
    'type': 'tabs',
    'items': [
      {'title': 'Driver', 'icon': 'directions_car', 'route': '/driver'},
      {'title': 'Trip', 'icon': 'receipt', 'route': '/passenger'},
    ],
  },
  'state': {'initial': {'live': _initialState}},
  'onInit': {'type': 'batch', 'actions': [{'type': 'resource', 'action': 'subscribe', 'uri': 'trip://state', 'binding': 'live'}, {'type': 'resource', 'action': 'read', 'uri': 'trip://state', 'binding': 'live'}]},
};

/// Spec 11.6 — what a launcher shows before loading anything.
const Map<String, dynamic> appInfoDefinition = {
  'id': 'city.taxi.dashboard',
  'title': 'Taxi — dashboard and trip',
  'description': 'One meter, seen from the front seat and from the back.',
  'version': '1.0.0',
  'publisher': {'name': 'City Taxi'},
};

Map<String, dynamic> _row(String label, String value,
        {String color = _ink, double size = 15}) =>
    {
      'type': 'linear',
      'direction': 'horizontal',
      'crossAxisAlignment': 'center',
      'children': [
        {
          'type': 'text',
          'content': label,
          'style': {'fontSize': 13, 'color': _muted},
        },
        {'type': 'spacer'},
        {
          'type': 'text',
          'content': value,
          'style': {'fontSize': size, 'fontFamily': _mono, 'color': color},
        },
      ],
    };

Map<String, dynamic> _card(Map<String, dynamic> child) => {
      'type': 'container',
      'padding': {'all': 18},
      'decoration': {
        'color': _surface,
        'borderRadius': 14,
        'border': {'color': _hair, 'width': 1},
      },
      'child': child,
    };

// ---------------------------------------------------------------------------
// Driver — in the dash, read at a glance and never touched while moving.
// ---------------------------------------------------------------------------
final Map<String, dynamic> driverDefinition = {
  'type': 'page',
  'metadata': {'title': 'Taxi Dashboard'},
  'onInit': {'type': 'batch', 'actions': [{'type': 'resource', 'action': 'subscribe', 'uri': 'trip://state', 'binding': 'live'}, {'type': 'resource', 'action': 'read', 'uri': 'trip://state', 'binding': 'live'}]},
  'state': {'initial': {'live': _initialState}},
  'content': {
    'type': 'container',
    'decoration': {'color': _canvas},
    'padding': {'all': 24},
    'child': {
      'type': 'linear',
      'direction': 'vertical',
      'gap': 18,
      'crossAxisAlignment': 'stretch',
      'children': [
        {
          'type': 'linear',
          'direction': 'horizontal',
          'crossAxisAlignment': 'center',
          'children': [
            {
              'type': 'linear',
              'direction': 'vertical',
              'gap': 4,
              'children': [
                {
                  'type': 'text',
                  'content': '{{live.plate}}',
                  'style': {
                    'fontSize': 13,
                    'fontFamily': _mono,
                    'color': _muted,
                    'letterSpacing': 2.0
                  },
                },
                {
                  'type': 'text',
                  'content': '{{live.status}}',
                  'style': {
                    'fontSize': 22,
                    'fontWeight': 'bold',
                    'color': _accent
                  },
                },
              ],
            },
            {'type': 'spacer'},
            {
              'type': 'text',
              'content': '{{live.kphLabel}}',
              'style': {'fontSize': 20, 'fontFamily': _mono, 'color': _ink},
            },
          ],
        },
        // Spec 2.15 — `expanded` divides space its parent has. In a column
        // that sizes itself by its children there is none to divide, and the
        // row asks for infinite height. The author decides the size, so the
        // band the two cards live in is stated here.
        {
          'type': 'box',
          'height': 196,
          'child': {
          'type': 'linear',
          'direction': 'horizontal',
          'gap': 18,
          'crossAxisAlignment': 'stretch',
          'children': [
            {
              'type': 'expanded',
              'flex': 3,
              'child': _card({
                'type': 'linear',
                'direction': 'vertical',
                'gap': 6,
                'children': [
                  {
                    'type': 'text',
                    'content': 'FARE',
                    'style': {
                      'fontSize': 11,
                      'color': _muted,
                      'letterSpacing': 1.8
                    },
                  },
                  {
                    'type': 'linear',
                    'direction': 'horizontal',
                    'crossAxisAlignment': 'end',
                    'children': [
                      {
                        'type': 'text',
                        'content': '{{live.fareLabel}}',
                        'style': {
                          'fontSize': 64,
                          'fontFamily': _mono,
                          'fontWeight': 'bold',
                          'color': _ink
                        },
                      },
                      {
                        'type': 'container',
                        'padding': {'left': 10, 'bottom': 12},
                        'child': {
                          'type': 'text',
                          'content': '',
                          'style': {'fontSize': 18, 'color': _muted},
                        },
                      },
                    ],
                  },
                ],
              }),
            },
            {
              'type': 'expanded',
              'flex': 2,
              'child': _card({
                'type': 'linear',
                'direction': 'vertical',
                'gap': 12,
                'children': [
                  {
                    'type': 'text',
                    'content': 'THIS TRIP',
                    'style': {
                      'fontSize': 11,
                      'color': _muted,
                      'letterSpacing': 1.8
                    },
                  },
                  _row('Distance', '{{live.distanceLabel}}'),
                  _row('Waiting', '{{live.waitingLabel}}'),
                  _row('Approval', '{{live.approval}}', color: _muted, size: 14),
                ],
              }),
            },
          ],
          },
        },
        {'type': 'spacer'},
        {
          'type': 'linear',
          'direction': 'horizontal',
          'crossAxisAlignment': 'center',
          'children': [
            {
              'type': 'text',
              'content': '{{live.meterRule}}',
              'style': {'fontSize': 12, 'color': _muted},
            },
            {'type': 'spacer'},
            {
              'type': 'text',
              'content':
                  'meter runs on {{live.framesUsed}} vehicle frames — no button pressed',
              'style': {'fontSize': 12, 'color': _muted},
            },
          ],
        },
        {
          'type': 'text',
          'content': '{{live.notice}}',
          'style': {'fontSize': 13, 'color': _accent},
        },
      ],
    },
  },
};

// ---------------------------------------------------------------------------
// Passenger — a tablet in the back. What am I being charged, and how do I pay.
// ---------------------------------------------------------------------------
final Map<String, dynamic> passengerDefinition = {
  'type': 'page',
  'metadata': {'title': 'Your Trip'},
  'onInit': {'type': 'batch', 'actions': [{'type': 'resource', 'action': 'subscribe', 'uri': 'trip://state', 'binding': 'live'}, {'type': 'resource', 'action': 'read', 'uri': 'trip://state', 'binding': 'live'}]},
  'state': {'initial': {'live': _initialState}},
  'content': {
    'type': 'container',
    'decoration': {'color': _canvas},
    'padding': {'all': 24},
    'child': {
      'type': 'linear',
      'direction': 'vertical',
      'gap': 16,
      'crossAxisAlignment': 'stretch',
      'children': [
        {
          'type': 'linear',
          'direction': 'vertical',
          'gap': 4,
          'children': [
            {
              'type': 'text',
              'content': 'YOUR TRIP',
              'style': {
                'fontSize': 12,
                'color': _muted,
                'letterSpacing': 2.2
              },
            },
            {
              'type': 'text',
              'content': '{{live.plate}}',
              'style': {'fontSize': 18, 'fontFamily': _mono, 'color': _ink},
            },
          ],
        },
        _card({
          'type': 'linear',
          'direction': 'vertical',
          'gap': 10,
          'children': [
            {
              'type': 'linear',
              'direction': 'horizontal',
              'crossAxisAlignment': 'end',
              'children': [
                {
                  'type': 'text',
                  'content': '{{live.fareLabel}}',
                  'style': {
                    'fontSize': 52,
                    'fontFamily': _mono,
                    'fontWeight': 'bold',
                    'color': _ink
                  },
                },
                {
                  'type': 'container',
                  'padding': {'left': 8, 'bottom': 10},
                  'child': {
                    'type': 'text',
                    'content': '',
                    'style': {'fontSize': 16, 'color': _muted},
                  },
                },
                {'type': 'spacer'},
                {
                  'type': 'text',
                  'content': '{{live.distanceLabel}}',
                  'style': {
                    'fontSize': 16,
                    'fontFamily': _mono,
                    'color': _muted
                  },
                },
              ],
            },
            {'type': 'divider', 'color': _hair},
            // The breakdown is the passenger's side of the meter rule: three
            // lines that add up to the number above them.
            _row('Flagfall', '{{live.flagfallLabel}}'),
            _row('Distance', '{{live.distanceChargeLabel}}'),
            _row('Waiting', '{{live.waitingChargeLabel}}'),
          ],
        }),
        {
          'type': 'conditional',
          'condition': '{{live.payDue}}',
          'then': {
            'type': 'container',
            'padding': {'all': 18},
            'decoration': {'color': _paid, 'borderRadius': 14},
            'child': {
              'type': 'linear',
              'direction': 'vertical',
              'gap': 12,
              'crossAxisAlignment': 'stretch',
              'children': [
                {
                  'type': 'text',
                  'content': 'Arrived — pay here, or with the driver',
                  'style': {
                    'fontSize': 15,
                    'fontWeight': 'bold',
                    'color': _onPaid
                  },
                },
                {
                  'type': 'button',
                  'label': 'Pay {{live.fareLabel}} by card',
                  'variant': 'filled',
                  'fullWidth': true,
                  'onTap': {
                    'type': 'tool',
                    'tool': 'fare.charge',
                    'params': {}
                  },
                },
              ],
            },
          },
          'else': {
            'type': 'text',
            'content': '{{live.meterRule}}',
            'style': {'fontSize': 13, 'color': _muted},
          },
        },
        {'type': 'spacer'},
        {
          'type': 'linear',
          'direction': 'horizontal',
          'crossAxisAlignment': 'center',
          'children': [
            {
              'type': 'text',
              'content': 'Approval {{live.approval}}',
              'style': {'fontSize': 13, 'fontFamily': _mono, 'color': _muted},
            },
            {'type': 'spacer'},
            {
              'type': 'text',
              'content': '{{live.notice}}',
              'style': {'fontSize': 13, 'color': _accent},
            },
          ],
        },
      ],
    },
  },
};
