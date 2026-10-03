import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_editor_page.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_preview_page.dart';
import 'package:mobileapp/seller_space/sale/listing/photos/listing_photos_page.dart';
import 'package:mobileapp/seller_space/sale/sale_activation_page.dart';
import 'package:mobileapp/seller_space/sale/sale_route_scope.dart';

const _saleId = 'saleId';

/// The routes of a sale (EPIC-08), children of `/vendeur`, pushed above
/// the tabs on [navigatorKey]: `ventes/<id>` (activation of its formula),
/// `ventes/<id>/annonce` (V11a) with `photos` and `apercu`.
List<RouteBase> saleRoutes(GlobalKey<NavigatorState> navigatorKey) => [
  GoRoute(
    parentNavigatorKey: navigatorKey,
    path:
        '${AppRoutes.sellerSales.substring(AppRoutes.seller.length + 1)}'
        '/:$_saleId',
    builder: (context, state) => _sale(state, const SaleActivationPage()),
    routes: [
      GoRoute(
        parentNavigatorKey: navigatorKey,
        path: 'annonce',
        builder: (context, state) => _sale(state, const ListingEditorPage()),
        routes: [
          GoRoute(
            parentNavigatorKey: navigatorKey,
            path: 'photos',
            builder: (context, state) =>
                _sale(state, const ListingPhotosPage()),
          ),
          GoRoute(
            parentNavigatorKey: navigatorKey,
            path: 'apercu',
            builder: (context, state) =>
                _sale(state, const ListingPreviewPage()),
          ),
        ],
      ),
    ],
  ),
];

Widget _sale(GoRouterState state, Widget page) =>
    SaleRouteScope(saleId: state.pathParameters[_saleId]!, child: page);
