class AppStrings {
  AppStrings._();

  // ── App Info ──────────────────────────────────────────────────────────────
  static const String appName = 'Chấm Công Trạm BLAO';
  static const String appTagline = 'Trạm trà - Trạm bánh';
  static const String appVersion = 'Phiên bản 1.1.0';
  static const String blaoStationRegion = 'Cao nguyên Bảo Lộc • Đà Lạt';
  static const String blaoStationSopTitle = 'Cẩm nang & Hẹn giờ Quầy BLAO';
  static const String blaoStationSopSubtitle = 'Tiêu chuẩn lò Bánh Lăn Nướng & ủ Trà Ô Long';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String login = 'Đăng nhập';
  static const String register = 'Đăng ký';
  static const String logout = 'Đăng xuất';
  static const String email = 'Email';
  static const String password = 'Mật khẩu';
  static const String confirmPassword = 'Xác nhận mật khẩu';
  static const String forgotPassword = 'Quên mật khẩu?';
  static const String resetPassword = 'Đặt lại mật khẩu';
  static const String sendResetEmail = 'Gửi email đặt lại mật khẩu';
  static const String fullName = 'Họ và tên';
  static const String phoneNumber = 'Số điện thoại';
  static const String emailHint = 'Nhập địa chỉ email';
  static const String passwordHint = 'Nhập mật khẩu (ít nhất 6 ký tự)';
  static const String confirmPasswordHint = 'Nhập lại mật khẩu';
  static const String fullNameHint = 'Nhập họ và tên đầy đủ';
  static const String phoneHint = 'Nhập số điện thoại';
  static const String haveAccount = 'Đã có tài khoản?';
  static const String noAccount = 'Chưa có tài khoản?';
  static const String profileSetup = 'Thiết lập hồ sơ';
  static const String profileSetupSubtitle =
      'Hoàn thiện thông tin để bắt đầu sử dụng';
  static const String continueButton = 'Tiếp tục';
  static const String skip = 'Bỏ qua';
  static const String chooseAvatar = 'Chọn ảnh đại diện';
  static const String takePhoto = 'Chụp ảnh';
  static const String chooseFromGallery = 'Chọn từ thư viện';

  // ── Welcome ───────────────────────────────────────────────────────────────
  static const String welcome = 'Chào mừng';
  static const String welcomeSubtitle = 'Bắt đầu quản lý chấm công thông minh';
  static const String createStore = 'Tạo cửa hàng';
  static const String createStoreSubtitle = 'Dành cho chủ cửa hàng';
  static const String joinStore = 'Tham gia cửa hàng';
  static const String joinStoreSubtitle = 'Dành cho nhân viên và quản lý';

  // ── Store ─────────────────────────────────────────────────────────────────
  static const String storeName = 'Tên cửa hàng';
  static const String storeCode = 'Mã cửa hàng';
  static const String storeAddress = 'Địa chỉ';
  static const String storeWifi = 'Tên WiFi (SSID)';
  static const String storeRadius = 'Bán kính chấm công (mét)';
  static const String storeSettings = 'Cài đặt cửa hàng';
  static const String createStoreButton = 'Tạo cửa hàng';
  static const String storeNameHint = 'Nhập tên cửa hàng';
  static const String storeAddressHint = 'Nhập địa chỉ cửa hàng';
  static const String storeWifiHint = 'Tên WiFi tại cửa hàng';
  static const String enterStoreCode = 'Nhập mã cửa hàng';
  static const String storeCodeHint = 'Nhập mã 6 ký tự';
  static const String joinByCode = 'Tham gia bằng mã';
  static const String joinByQr = 'Quét mã QR';
  static const String scanQrCode = 'Quét mã QR';
  static const String scanQrInstruction = 'Hướng camera vào mã QR của cửa hàng';
  static const String generateQr = 'Tạo mã QR';
  static const String shareQr = 'Chia sẻ mã QR';
  static const String copyCode = 'Sao chép mã';
  static const String codeCopied = 'Đã sao chép mã';
  static const String myStoreCode = 'Mã cửa hàng của bạn';

  // ── Check-In/Out ──────────────────────────────────────────────────────────
  static const String checkIn = 'Chấm vào';
  static const String checkOut = 'Chấm ra';
  static const String checkInSuccess = 'Chấm vào thành công!';
  static const String checkOutSuccess = 'Chấm ra thành công!';
  static const String checkingIn = 'Đang chấm vào...';
  static const String checkingOut = 'Đang chấm ra...';
  static const String attendanceHistory = 'Lịch sử chấm công';
  static const String todayAttendance = 'Hôm nay';
  static const String workingHours = 'Giờ làm việc';
  static const String totalHours = 'Tổng giờ';
  static const String checkInTime = 'Giờ vào';
  static const String checkOutTime = 'Giờ ra';
  static const String checkInMethod = 'Phương thức';
  static const String noAttendanceToday = 'Chưa có dữ liệu chấm công hôm nay';
  static const String lateCheckIn = 'Đi muộn';
  static const String earlyCheckOut = 'Về sớm';

  // ── Check-In Methods ──────────────────────────────────────────────────────
  static const String methodWifi = 'WiFi';
  static const String methodGps = 'GPS';
  static const String methodManual = 'Thủ công';
  static const String methodQr = 'Mã QR';

  // ── Attendance Status ─────────────────────────────────────────────────────
  static const String statusWorking = 'Đang làm việc';
  static const String statusNotStarted = 'Chưa vào ca';
  static const String statusFinished = 'Đã kết thúc ca';
  static const String statusPending = 'Chờ duyệt';
  static const String statusAbsent = 'Vắng mặt';
  static const String statusLeave = 'Nghỉ phép';

  // ── Roles ─────────────────────────────────────────────────────────────────
  static const String roleOwner = 'Chủ';
  static const String roleManager = 'Quản lý';
  static const String roleEmployee = 'Nhân viên';

  // ── Employee Type ─────────────────────────────────────────────────────────
  static const String typeFulltime = 'Toàn thời gian';
  static const String typeParttime = 'Bán thời gian';
  static const String fulltimeShort = 'Full-time';
  static const String parttimeShort = 'Part-time';

  // ── Member Status ─────────────────────────────────────────────────────────
  static const String memberPending = 'Chờ duyệt';
  static const String memberActive = 'Hoạt động';
  static const String memberKicked = 'Đã xóa';

  // ── Members ───────────────────────────────────────────────────────────────
  static const String members = 'Nhân viên';
  static const String memberList = 'Danh sách nhân viên';
  static const String addMember = 'Thêm nhân viên';
  static const String editMember = 'Chỉnh sửa thông tin';
  static const String removeMember = 'Xóa khỏi cửa hàng';
  static const String approveMember = 'Duyệt tham gia';
  static const String rejectMember = 'Từ chối';
  static const String pendingRequests = 'Yêu cầu chờ duyệt';
  static const String noMembers = 'Chưa có nhân viên nào';
  static const String noPendingRequests = 'Không có yêu cầu chờ duyệt';
  static const String memberApproved = 'Đã duyệt thành công';
  static const String memberRejected = 'Đã từ chối';
  static const String memberRemoved = 'Đã xóa nhân viên';

  // ── Schedule ──────────────────────────────────────────────────────────────
  static const String schedule = 'Lịch làm việc';
  static const String weeklySchedule = 'Lịch tuần';
  static const String assignSchedule = 'Phân ca làm việc';
  static const String saveSchedule = 'Lưu lịch';
  static const String scheduleUpdated = 'Đã cập nhật lịch làm việc';
  static const String noSchedule = 'Chưa có lịch làm việc';
  static const String thisWeek = 'Tuần này';
  static const String nextWeek = 'Tuần sau';
  static const String previousWeek = 'Tuần trước';

  // ── Shifts ────────────────────────────────────────────────────────────────
  static const String shiftMorning = 'Ca sáng';
  static const String shiftAfternoon = 'Ca chiều';
  static const String shiftEvening = 'Ca tối';
  static const String shiftOff = 'Nghỉ';

  // ── Days of Week ──────────────────────────────────────────────────────────
  static const String monday = 'Thứ 2';
  static const String tuesday = 'Thứ 3';
  static const String wednesday = 'Thứ 4';
  static const String thursday = 'Thứ 5';
  static const String friday = 'Thứ 6';
  static const String saturday = 'Thứ 7';
  static const String sunday = 'CN';

  // ── Salary ────────────────────────────────────────────────────────────────
  static const String salary = 'Lương';
  static const String salaryReport = 'Bảng lương';
  static const String monthlySalary = 'Lương tháng';
  static const String hourlyRate = 'Lương theo giờ';
  static const String baseSalary = 'Lương cơ bản';
  static const String calculatedSalary = 'Lương thực tế';
  static const String standardHours = 'Giờ chuẩn';
  static const String totalWorkedHours = 'Tổng giờ làm';
  static const String salaryMonth = 'Tháng lương';
  static const String exportSalary = 'Xuất bảng lương';
  static const String exportExcel = 'Xuất Excel';
  static const String noSalaryData = 'Chưa có dữ liệu lương';
  static const String salaryCalculated = 'Đã tính lương';
  static const String calculateSalary = 'Tính lương';

  // ── Dashboard ─────────────────────────────────────────────────────────────
  static const String dashboard = 'Bảng điều khiển';
  static const String overview = 'Tổng quan';
  static const String todaySummary = 'Tổng hợp hôm nay';
  static const String staffPresent = 'Nhân viên có mặt';
  static const String staffAbsent = 'Nhân viên vắng';
  static const String recentActivity = 'Hoạt động gần đây';
  static const String viewAll = 'Xem tất cả';

  // ── Navigation ────────────────────────────────────────────────────────────
  static const String home = 'Trang chủ';
  static const String historyNav = 'Lịch sử';
  static const String scheduleNav = 'Lịch làm';
  static const String salaryNav = 'Lương';
  static const String settingsNav = 'Cài đặt';
  static const String profileNav = 'Hồ sơ';
  static const String membersNav = 'Nhân viên';

  // ── Buttons ───────────────────────────────────────────────────────────────
  static const String save = 'Lưu';
  static const String cancel = 'Hủy';
  static const String confirm = 'Xác nhận';
  static const String delete = 'Xóa';
  static const String edit = 'Chỉnh sửa';
  static const String close = 'Đóng';
  static const String back = 'Quay lại';
  static const String next = 'Tiếp theo';
  static const String done = 'Hoàn thành';
  static const String retry = 'Thử lại';
  static const String share = 'Chia sẻ';
  static const String copy = 'Sao chép';
  static const String approve = 'Duyệt';
  static const String reject = 'Từ chối';
  static const String remove = 'Xóa';
  static const String update = 'Cập nhật';
  static const String refresh = 'Làm mới';

  // ── Pending Approval ──────────────────────────────────────────────────────
  static const String pendingApproval = 'Chờ duyệt';
  static const String pendingApprovalTitle = 'Yêu cầu đang chờ duyệt';
  static const String pendingApprovalMessage =
      'Yêu cầu tham gia của bạn đang được quản lý xét duyệt. '
      'Vui lòng chờ thông báo.';
  static const String pendingApprovalWaiting = 'Đang chờ quản lý duyệt...';

  // ── Error Messages ────────────────────────────────────────────────────────
  static const String errorGeneral = 'Có lỗi xảy ra, vui lòng thử lại';
  static const String errorNetwork =
      'Lỗi kết nối mạng, vui lòng kiểm tra lại';
  static const String errorInvalidEmail = 'Địa chỉ email không hợp lệ';
  static const String errorWeakPassword = 'Mật khẩu phải có ít nhất 6 ký tự';
  static const String errorPasswordMismatch = 'Mật khẩu không khớp';
  static const String errorEmailInUse = 'Email này đã được sử dụng';
  static const String errorWrongPassword = 'Email hoặc mật khẩu không đúng';
  static const String errorUserNotFound = 'Tài khoản không tồn tại';
  static const String errorRequiredField = 'Vui lòng điền thông tin này';
  static const String errorInvalidCode = 'Mã cửa hàng không hợp lệ';
  static const String errorStoreNotFound = 'Không tìm thấy cửa hàng';
  static const String errorAlreadyMember = 'Bạn đã là thành viên cửa hàng này';
  static const String errorLocationPermission =
      'Cần cấp quyền truy cập vị trí';
  static const String errorWifiPermission = 'Cần cấp quyền truy cập WiFi';
  static const String errorCameraPermission = 'Cần cấp quyền truy cập camera';
  static const String errorOutOfRange =
      'Bạn không ở trong phạm vi cửa hàng để chấm công';
  static const String errorWrongWifi =
      'Bạn không kết nối WiFi cửa hàng để chấm công';
  static const String errorAlreadyCheckedIn = 'Bạn đã chấm vào hôm nay';
  static const String errorNotCheckedIn = 'Bạn chưa chấm vào hôm nay';
  static const String errorNameRequired = 'Vui lòng nhập họ và tên';
  static const String errorStoreNameRequired = 'Vui lòng nhập tên cửa hàng';
  static const String errorPermissionDenied =
      'Bạn không có quyền thực hiện thao tác này';

  // ── Success Messages ──────────────────────────────────────────────────────
  static const String successLogin = 'Đăng nhập thành công';
  static const String successRegister = 'Đăng ký thành công';
  static const String successLogout = 'Đã đăng xuất';
  static const String successProfileUpdate = 'Cập nhật hồ sơ thành công';
  static const String successStoreCreated = 'Tạo cửa hàng thành công';
  static const String successJoinRequest = 'Đã gửi yêu cầu tham gia';
  static const String successSaved = 'Đã lưu thành công';
  static const String successExported = 'Xuất file thành công';
  static const String successPasswordReset =
      'Email đặt lại mật khẩu đã được gửi';

  // ── Confirmation Dialogs ──────────────────────────────────────────────────
  static const String confirmLogout = 'Xác nhận đăng xuất';
  static const String confirmLogoutMessage =
      'Bạn có chắc chắn muốn đăng xuất không?';
  static const String confirmRemoveMember = 'Xác nhận xóa nhân viên';
  static const String confirmRemoveMemberMessage =
      'Bạn có chắc chắn muốn xóa nhân viên này khỏi cửa hàng?';
  static const String confirmCheckOut = 'Xác nhận chấm ra';
  static const String confirmCheckOutMessage =
      'Bạn có chắc chắn muốn chấm ra không?';

  // ── Empty States ──────────────────────────────────────────────────────────
  static const String emptyAttendance = 'Chưa có dữ liệu chấm công';
  static const String emptyMembers = 'Chưa có nhân viên nào';
  static const String emptySchedule = 'Chưa có lịch làm việc';
  static const String emptySalary = 'Chưa có dữ liệu lương';
  static const String emptyHistory = 'Chưa có lịch sử';
  static const String emptySearch = 'Không tìm thấy kết quả';

  // ── Misc ──────────────────────────────────────────────────────────────────
  static const String loading = 'Đang tải...';
  static const String processing = 'Đang xử lý...';
  static const String noData = 'Không có dữ liệu';
  static const String today = 'Hôm nay';
  static const String yesterday = 'Hôm qua';
  static const String thisMonth = 'Tháng này';
  static const String search = 'Tìm kiếm';
  static const String filter = 'Lọc';
  static const String sort = 'Sắp xếp';
  static const String hour = 'giờ';
  static const String minute = 'phút';
  static const String hours = 'giờ';
  static const String hoursUnit = 'h';
  static const String currencyUnit = '₫';
  static const String kmUnit = 'km';
  static const String meterUnit = 'm';
}
