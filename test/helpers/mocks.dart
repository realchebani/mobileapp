import 'package:auth_repository/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository;

class MockProfileRepository extends Mock implements ProfileRepository;

class MockPropertyRepository extends Mock implements PropertyRepository;

class MockSellerTunnelCubit extends MockCubit<SellerTunnelState>
    implements SellerTunnelCubit;

class MockOnboardingRepository extends Mock implements OnboardingRepository;

class MockAppBloc extends MockBloc<AppEvent, AppState> implements AppBloc;

class MockLoginCubit extends MockCubit<LoginState> implements LoginCubit;

class MockProfileCubit extends MockCubit<ProfileState> implements ProfileCubit;

class MockGoRouter extends Mock implements GoRouter;
