import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/models.dart';

// Retrofit generiše implementaciju ovog interfejsa u 'api_service.g.dart'.
part 'api_service.g.dart';

/// Spisak SVIH poziva ka serveru, na jednom mjestu.
///
/// Pišemo samo „potpise“ metoda i anotacije (npr. @GET), a Retrofit kroz
/// build_runner napiše stvarni kod koji poziva Dio. Datumski parametri se
/// šalju kao ISO tekst (String) da bi server pravilno razumio vrijeme.
@RestApi()
abstract class ApiService {
  factory ApiService(Dio dio, {String baseUrl}) = _ApiService;

  // ----------------------- AUTENTIKACIJA -----------------------

  @POST('/api/auth/login')
  Future<TokenPair> login(@Body() LoginRequest body);

  @POST('/api/auth/refresh')
  Future<TokenPair> refresh(@Body() RefreshRequest body);

  @POST('/api/auth/logout')
  Future<void> logout(@Body() LogoutRequest body);

  // ----------------------- KLIJENTI (paginacija) -----------------------

  @GET('/api/customers')
  Future<PageCustomerResponse> getCustomers({
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/customers/{id}')
  Future<CustomerResponse> getCustomer(@Path('id') int id);

  @POST('/api/customers')
  Future<CustomerResponse> createCustomer(@Body() CustomerRequest body);

  @PUT('/api/customers/{id}')
  Future<CustomerResponse> updateCustomer(
    @Path('id') int id,
    @Body() CustomerRequest body,
  );

  @DELETE('/api/customers/{id}')
  Future<void> deleteCustomer(@Path('id') int id);

  @GET('/api/customers/search')
  Future<List<CustomerSearchHit>> searchCustomers(@Query('name') String name);

  @GET('/api/customers/by-phone')
  Future<List<CustomerResponse>> findCustomersByPhone(
      @Query('phone') String phone);

  // ----------------------- ZAPOSLENI -----------------------

  @GET('/api/employees')
  Future<List<EmployeeResponse>> getEmployees();

  @GET('/api/employees/{id}')
  Future<EmployeeResponse> getEmployee(@Path('id') int id);

  @POST('/api/employees')
  Future<EmployeeResponse> createEmployee(@Body() EmployeeRequest body);

  @PUT('/api/employees/{id}')
  Future<EmployeeResponse> updateEmployee(
    @Path('id') int id,
    @Body() EmployeeRequest body,
  );

  @DELETE('/api/employees/{id}')
  Future<void> deleteEmployee(@Path('id') int id);

  // ----------------------- USLUGE -----------------------

  @GET('/api/services')
  Future<List<ServiceEntityResponse>> getServices();

  @POST('/api/services')
  Future<ServiceEntityResponse> createService(@Body() ServiceEntityRequest body);

  @PUT('/api/services/{id}')
  Future<ServiceEntityResponse> updateService(
    @Path('id') int id,
    @Body() ServiceEntityRequest body,
  );

  @DELETE('/api/services/{id}')
  Future<void> deleteService(@Path('id') int id);

  // ----------------------- PROIZVODI -----------------------

  @GET('/api/products')
  Future<List<ProductResponse>> getProducts();

  @POST('/api/products')
  Future<ProductResponse> createProduct(@Body() ProductRequest body);

  @PUT('/api/products/{id}')
  Future<ProductResponse> updateProduct(
    @Path('id') int id,
    @Body() ProductRequest body,
  );

  @DELETE('/api/products/{id}')
  Future<void> deleteProduct(@Path('id') int id);

  // ----------------------- DOBAVLJAČI (paginacija + CRUD) -----------------------

  @GET('/api/suppliers')
  Future<PageSupplierResponse> getSuppliers({
    @Query('name') String? name,
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/suppliers/{id}')
  Future<SupplierResponse> getSupplier(@Path('id') int id);

  @POST('/api/suppliers')
  Future<SupplierResponse> createSupplier(@Body() SupplierRequest body);

  @PUT('/api/suppliers/{id}')
  Future<SupplierResponse> updateSupplier(
    @Path('id') int id,
    @Body() SupplierRequest body,
  );

  @DELETE('/api/suppliers/{id}')
  Future<void> deleteSupplier(@Path('id') int id);

  // ----------------------- ULOGE / PRODAJNA MJESTA (za padajuće liste) -----------------------

  @GET('/api/roles')
  Future<List<RoleResponse>> getRoles();

  @GET('/api/selling-places')
  Future<List<SellingPlaceResponse>> getSellingPlaces();

  // ----------------------- TERMINI (paginacija + filteri) -----------------------

  @GET('/api/appointments')
  Future<PageAppointmentResponse> getAppointments({
    @Query('from') String? from, // ISO datum-vrijeme
    @Query('to') String? to,
    @Query('status') String? status,
    @Query('employeeId') int? employeeId,
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/appointments/{id}')
  Future<AppointmentResponse> getAppointment(@Path('id') int id);

  @POST('/api/appointments')
  Future<AppointmentResponse> createAppointment(@Body() AppointmentRequest body);

  @PUT('/api/appointments/{id}')
  Future<AppointmentResponse> updateAppointment(
    @Path('id') int id,
    @Body() AppointmentRequest body,
  );

  @DELETE('/api/appointments/{id}')
  Future<void> deleteAppointment(@Path('id') int id);

  @PATCH('/api/appointments/{id}/status')
  Future<AppointmentResponse> changeAppointmentStatus(
    @Path('id') int id,
    @Body() StatusChangeRequest body,
  );

  // ----------------------- IZVJEŠTAJI -----------------------

  @GET('/api/reports/shop')
  Future<RevenueSummary> shopRevenue({
    @Query('from') required String from,
    @Query('to') required String to,
  });

  @GET('/api/reports/me')
  Future<RevenueSummary> myRevenue({
    @Query('from') required String from,
    @Query('to') required String to,
  });

  @GET('/api/reports/shop/top-employees')
  Future<List<EmployeeRevenue>> topEmployees({
    @Query('from') required String from,
    @Query('to') required String to,
    @Query('limit') int limit = 5,
  });

  @GET('/api/reports/shop/by-employee')
  Future<List<EmployeeRevenue>> revenueByEmployee({
    @Query('from') required String from,
    @Query('to') required String to,
  });

  @GET('/api/reports/shop/revenue-over-time')
  Future<List<RevenueBucket>> revenueOverTime({
    @Query('from') required String from,
    @Query('to') required String to,
    @Query('bucket') String bucket = 'day',
  });
}
