import type { Metadata } from "next";
import Link from "next/link";
import { Bullets, LegalPage, Section } from "@/components/LegalPage";
import { LEGAL, privacyMailto } from "@/lib/legal-config";

export const metadata: Metadata = {
  title: "Yêu Cầu Xóa Tài Khoản & Dữ Liệu Cá Nhân • POS Trạm BLAO",
  description:
    "Quy trình xóa tài khoản và dữ liệu cá nhân theo quy định Apple App Store Review Guideline 5.1.1(v) cho ứng dụng POS Trạm BLAO.",
};

export default function DeleteAccountPage() {
  const mail = privacyMailto("Yêu cầu xóa tài khoản - POS Trạm BLAO");

  return (
    <LegalPage title="Quy Trình & Yêu Cầu Xóa Tài Khoản (Account Deletion)" updated={LEGAL.effectiveDate}>
      <p>
        Tuân thủ quy chuẩn bảo mật và quyền riêng tư của <strong>Apple App Store (Guideline 5.1.1(v))</strong> và{" "}
        <strong>Google Play Console</strong>, người dùng ứng dụng <strong>{LEGAL.appName}</strong> có toàn quyền tự xóa
        tài khoản hoặc gửi yêu cầu xóa vĩnh viễn tài khoản và dữ liệu cá nhân của mình bất kỳ lúc nào.
      </p>

      <Section title="1. Cách 1: Tự xóa tài khoản trực tiếp trong ứng dụng di động (Tức thì)">
        <p>
          Bạn có thể tự thực hiện thao tác xóa tài khoản ngay trên thiết bị iPad / iPhone mà không cần phải chờ đợi phê duyệt:
        </p>
        <Bullets
          items={[
            <><strong>Bước 1:</strong> Mở ứng dụng <strong>{LEGAL.appName}</strong> trên thiết bị và đăng nhập vào tài khoản của bạn.</>,
            <><strong>Bước 2:</strong> Nhấn vào biểu tượng <strong>Menu chức năng (⋮)</strong> (ở góc trên màn hình Sơ đồ bàn đối với Thu ngân, hoặc màn hình Trung tâm Quản trị đối với Quản lý/Chủ quán).</>,
            <><strong>Bước 3:</strong> Chọn mục <strong>"Xóa tài khoản của tôi"</strong> (biểu tượng thẻ đỏ cảnh báo).</>,
            <><strong>Bước 4:</strong> Hộp thoại giải thích sẽ hiện ra. Bạn gõ chính xác chữ <code>XOA</code> vào ô xác nhận để tránh bấm nhầm.</>,
            <><strong>Bước 5:</strong> Nhấn nút <strong>Xóa tài khoản</strong>. Hệ thống sẽ ngay lập tức xóa dữ liệu tài khoản xác thực Firebase Auth, hủy phiên đăng nhập và xóa toàn bộ thông tin nhạy cảm của bạn khỏi máy chủ.</>,
          ]}
        />
      </Section>

      <Section title="2. Cách 2: Yêu cầu xóa tài khoản từ xa qua Email hỗ trợ">
        <p>
          Nếu bạn đã gỡ cài đặt ứng dụng hoặc không thể đăng nhập để tự thao tác, vui lòng gửi email yêu cầu hỗ trợ trực tiếp đến ban quản trị hệ thống:
        </p>
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-md)",
            padding: "16px 20px",
            margin: "12px 0",
          }}
        >
          <p style={{ margin: "4px 0" }}>
            • <strong>Email tiếp nhận:</strong>{" "}
            <a href={mail} style={{ color: "var(--primary-dark)", fontWeight: 700 }}>
              {LEGAL.contactEmail}
            </a>
          </p>
          <p style={{ margin: "4px 0" }}>
            • <strong>Hotline hỗ trợ:</strong>{" "}
            <a href={LEGAL.hotlineTel} style={{ color: "var(--primary-dark)", fontWeight: 700 }}>
              {LEGAL.hotline}
            </a>
          </p>
          <p style={{ margin: "4px 0" }}>
            • <strong>Tiêu đề email:</strong> <code>Yêu cầu xóa tài khoản - POS Trạm BLAO</code>
          </p>
          <p style={{ margin: "4px 0" }}>
            • <strong>Nội dung cần cung cấp:</strong> Tên đăng nhập, mã cửa hàng hoặc số điện thoại / email đã liên kết tài khoản cần xóa.
          </p>
        </div>
        <p style={{ fontSize: 13, color: "var(--subtext)" }}>
          <em>Thời gian phản hồi & xử lý: Chúng tôi cam kết xử lý và xác nhận kết quả xóa dữ liệu qua email trong vòng <strong>24 – 48 giờ làm việc</strong> (tối đa không quá 30 ngày theo quy định).</em>
        </p>
        {LEGAL.contactEmail && (
          <div style={{ marginTop: 14 }}>
            <a
              href={mail}
              style={{
                display: "inline-block",
                background: "var(--primary)",
                color: "var(--on-primary)",
                padding: "10px 20px",
                borderRadius: "var(--radius-md)",
                fontWeight: 700,
                fontSize: 14,
                textDecoration: "none",
              }}
            >
              Gửi email yêu cầu xóa tài khoản
            </a>
          </div>
        )}
      </Section>

      <Section title="3. Dữ liệu nào sẽ bị xóa và dữ liệu nào được lưu trữ?">
        <Bullets
          items={[
            <><strong>Dữ liệu xóa vĩnh viễn:</strong> Thông tin xác thực Firebase Authentication, thông tin hồ sơ người dùng (họ tên, username, số điện thoại, vai trò), các device tokens nhận thông báo.</>,
            <><strong>Tài khoản liên kết Chấm Công Trạm BLAO:</strong> Nếu bạn đăng nhập bằng tài khoản Chấm Công Trạm, liên kết xác thực giữa hai hệ thống sẽ bị gỡ bỏ hoàn toàn.</>,
            <><strong>Dữ liệu kế toán & lịch sử hóa đơn:</strong> Nhằm tuân thủ các quy định pháp luật về kế toán và phòng chống gian lận thương mại cho Chủ cửa hàng, các hóa đơn bán hàng và báo cáo ca két đã kết thúc mà bạn đã tạo trong quá khứ sẽ được giữ lại trong hệ thống sổ sách của cửa hàng, nhưng thông tin tài khoản người tạo sẽ chuyển thành trạng thái vô danh (Anonymous/Deactivated Staff).</>,
          ]}
        />
      </Section>

      <Section title="4. Đối với tài khoản Chủ quán (Root Owner)">
        <p>
          Nếu bạn là Chủ sở hữu cửa hàng (Root Owner), việc xóa tài khoản có thể ảnh hưởng đến quyền vận hành và truy cập dữ liệu của toàn bộ chi nhánh. Trước khi tiến hành xóa tài khoản, vui lòng liên hệ bộ phận hỗ trợ kỹ thuật qua email{" "}
          <a href={mail} style={{ color: "var(--primary-dark)", fontWeight: 600 }}>
            {LEGAL.contactEmail}
          </a>{" "}
          để chuyển giao quyền quản trị cửa hàng cho nhân sự kế nhiệm.
        </p>
      </Section>
    </LegalPage>
  );
}
