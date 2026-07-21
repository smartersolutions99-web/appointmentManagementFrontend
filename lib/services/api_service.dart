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

  // ----------------------- PROIZVODI (paginacija + CRUD) -----------------------

  @GET('/api/products')
  Future<PageProductResponse> getProducts({
    @Query('name') String? name,
    @Query('supplierId') int? supplierId,
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/products/{id}')
  Future<ProductResponse> getProduct(@Path('id') int id);

  @GET('/api/products/low-stock')
  Future<List<LowStockItem>> getLowStock({
    @Query('threshold') required int threshold,
  });

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

  // ----------------------- NABAVKE (stock-in) -----------------------

  @GET('/api/purchases')
  Future<PagePurchaseResponse> getPurchases({
    @Query('supplierId') int? supplierId,
    @Query('from') String? from,
    @Query('to') String? to,
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/purchases/{id}')
  Future<PurchaseResponse> getPurchase(@Path('id') int id);

  @POST('/api/purchases')
  Future<PurchaseResponse> createPurchase(@Body() PurchaseRequest body);

  // ----------------------- PRODAJE (POS / stock-out) -----------------------

  @GET('/api/sales')
  Future<PageSaleResponse> getSales({
    @Query('employeeId') int? employeeId, // samo ADMIN smije filtrirati po drugom
    @Query('isInternal') bool? isInternal,
    @Query('from') String? from,
    @Query('to') String? to,
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/sales/{id}')
  Future<SaleResponse> getSale(@Path('id') int id);

  @POST('/api/sales')
  Future<SaleResponse> createSale(@Body() SaleRequest body);

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

  // ----------------------- ŠABLONSKE SMJENE (paginacija + CRUD) -----------------------

  @GET('/api/shift-templates')
  Future<PageShiftTemplateResponse> getShiftTemplates({
    @Query('name') String? name,
    @Query('page') required int page,
    @Query('size') required int size,
    @Query('sort') String? sort,
  });

  @GET('/api/shift-templates/{id}')
  Future<ShiftTemplateResponse> getShiftTemplate(@Path('id') int id);

  @POST('/api/shift-templates')
  Future<ShiftTemplateResponse> createShiftTemplate(
      @Body() ShiftTemplateRequest body);

  @PUT('/api/shift-templates/{id}')
  Future<ShiftTemplateResponse> updateShiftTemplate(
    @Path('id') int id,
    @Body() ShiftTemplateRequest body,
  );

  @DELETE('/api/shift-templates/{id}')
  Future<void> deleteShiftTemplate(@Path('id') int id);

  // ----------------------- DODJELA SMJENA -----------------------

  @GET('/api/shift-assignments')
  Future<List<ShiftAssignmentResponse>> getShiftAssignments({
    @Query('from') String? from, // "YYYY-MM-DD"
    @Query('to') String? to,
  });

  @GET('/api/shift-assignments/{id}')
  Future<ShiftAssignmentResponse> getShiftAssignment(@Path('id') int id);

  @POST('/api/shift-assignments')
  Future<ShiftAssignmentResponse> createShiftAssignment(
      @Body() ShiftAssignmentRequest body);

  @PUT('/api/shift-assignments/{id}')
  Future<ShiftAssignmentResponse> updateShiftAssignment(
    @Path('id') int id,
    @Body() ShiftAssignmentRequest body,
  );

  @DELETE('/api/shift-assignments/{id}')
  Future<void> deleteShiftAssignment(@Path('id') int id);

  // ----------------------- RADNO VRIJEME -----------------------

  @GET('/api/working-hours')
  Future<List<WorkingHoursResponse>> getWorkingHours();

  /// Zamjena cijele sedmice: dani u nizu se upisuju, dani kojih nema se brišu
  /// (= salon zatvoren tog dana). Prazan niz = zatvoreno svih dana.
  @PUT('/api/working-hours')
  Future<List<WorkingHoursResponse>> replaceWorkingHours(
      @Body() List<WorkingHoursRequest> body);

  // ----------------------- RASPORED (kalendar) -----------------------

  @GET('/api/schedule')
  Future<List<ScheduleDayResponse>> getSchedule({
    @Query('employeeId') int? employeeId, // izostavi → server uzima svoj id
    @Query('from') required String from, // "YYYY-MM-DD"
    @Query('to') required String to,
  });

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
