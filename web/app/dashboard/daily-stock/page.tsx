"use client";
import { useEffect, useMemo, useState } from "react";
import { ref, onValue, get, update, query, orderByChild, startAt, endAt } from "firebase/database";
import { Calendar, ClipboardCheck, Download, Lock, Unlock, Save, Search, Sunrise, Sunset, Scale, History } from "lucide-react";
import { db } from "@/lib/firebase";
import { useAuth } from "@/lib/auth";
import { useDashboardData, sanitizeHistoryOrder } from "@/lib/data-context";
import { canAdjustPoints as isOwnerOrManager } from "@/lib/customers";
import { businessDateOf, businessDayRange, businessDayStartFor } from "@/lib/business-day";
import { exportStandardReportExcel } from "@/lib/export";
import { errorMessage } from "@/lib/errors";
import type { HistoryOrder } from "@/lib/reports";
import {
  buildVarianceRows,
  openingFromPrevious,
  parseQty,
  previousDate,
  soldQtyByProduct,
  summarizeVariance,
  VARIANCE_STATUS_LABEL,
  type DailyStockRecord,
  type StockProduct,
  type VarianceRow,
  type VarianceStatus,
} from "@/lib/daily-stock";

type Mode = "opening" | "closing" | "compare";
type Draft = Record<string, { opening?: string; received?: string; closing?: string }>;

const fmtQty = (n: number | null | undefined) =>
  n == null ? "—" : new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 3 }).format(n);

const fmtTime = (ts?: number) =>
  ts ? new Date(ts).toLocaleString("vi-VN", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit" }) : "";

const STATUS_COLOR: Record<VarianceStatus, string> = {
  MATCH: "#10b981",
  SHORT: "#ef4444",
  OVER: "#f59e0b",
  INCOMPLETE: "#6366f1",
  EMPTY: "#9ca3af",
};

export default function DailyStockPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, products, historyData } = useDashboardData();
  const { user } = useAuth();
  const isManager = isOwnerOrManager(user?.roleId || user?.role, user?.isRootOwner);

  const storeCode = currentStoreCode === "ALL" ? stores[0]?.storeCode || "" : currentStoreCode;
  const store = stores.find((s) => s.storeCode === storeCode);
  const startMinute = businessDayStartFor(storeCode);

  const [date, setDate] = useState(() => businessDateOf(Date.now(), startMinute));
  const [mode, setMode] = useState<Mode>("opening");
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("ALL");
  const [includeToppings, setIncludeToppings] = useState(false);
  const [onlyCounted, setOnlyCounted] = useState(false);
  const [tolerance, setTolerance] = useState("0");

  // Phiếu kiểm của ngày đang chọn + ngày trước (để gợi ý tồn đầu)
  const [record, setRecord] = useState<DailyStockRecord | null>(null);
  const [loadedKey, setLoadedKey] = useState("");
  const [prevRecord, setPrevRecord] = useState<DailyStockRecord | null>(null);
  // Nháp & thông báo gắn với (chi nhánh|ngày): đổi ngày / chi nhánh → tự bỏ nháp chưa lưu
  const [draftState, setDraftState] = useState<{ key: string; data: Draft }>({ key: "", data: {} });
  const [saving, setSaving] = useState(false);
  const [messageState, setMessageState] = useState<{ key: string; type: "ok" | "err"; text: string } | null>(null);
  const [nowTs] = useState(() => Date.now());

  // Hóa đơn của ngày (history giới hạn 150 bản gần nhất trong data-context → nạp thêm theo khoảng ngày)
  const [dayHistory, setDayHistory] = useState<HistoryOrder[]>([]);

  const recordKey = `${storeCode}|${date}`;
  const draft: Draft = useMemo(() => (draftState.key === recordKey ? draftState.data : {}), [draftState, recordKey]);
  const setDraft = (fn: (d: Draft) => Draft) =>
    setDraftState((s) => ({ key: recordKey, data: fn(s.key === recordKey ? s.data : {}) }));
  const message = messageState && messageState.key === recordKey ? messageState : null;
  const setMessage = (m: { type: "ok" | "err"; text: string } | null) => setMessageState(m ? { ...m, key: recordKey } : null);
  const loading = !!storeCode && loadedKey !== recordKey;

  useEffect(() => {
    if (!storeCode || !date) return;
    const key = `${storeCode}|${date}`;
    const unsub = onValue(
      ref(db, `stores/${storeCode}/daily_stock_counts/${date}`),
      (snap) => {
        setRecord(snap.exists() ? (snap.val() as DailyStockRecord) : null);
        setLoadedKey(key);
      },
      (err) => {
        setMessageState({ key, type: "err", text: `Không đọc được phiếu kiểm: ${err.message}` });
        setLoadedKey(key);
      }
    );
    get(ref(db, `stores/${storeCode}/daily_stock_counts/${previousDate(date)}`))
      .then((snap) => setPrevRecord(snap.exists() ? (snap.val() as DailyStockRecord) : null))
      .catch(() => setPrevRecord(null));
    return () => unsub();
  }, [storeCode, date]);

  useEffect(() => {
    if (!storeCode || !date) return;
    let cancelled = false;
    const { start, end } = businessDayRange(date, startMinute);
    const pad = 12 * 3600_000;
    get(query(ref(db, `stores/${storeCode}/history`), orderByChild("timestamp"), startAt(start - pad), endAt(end + pad)))
      .then((snap) => {
        if (cancelled) return;
        const list: HistoryOrder[] = [];
        snap.forEach((child) => {
          const h = sanitizeHistoryOrder(child.val(), child.key!);
          h.storeCode = h.storeCode || storeCode;
          list.push(h);
        });
        setDayHistory(list);
      })
      .catch(() => {
        if (!cancelled) setDayHistory([]);
      });
    return () => {
      cancelled = true;
    };
  }, [storeCode, date, startMinute]);

  const storeProducts: StockProduct[] = useMemo(
    () =>
      products
        .filter((p) => !p.storeCode || p.storeCode === storeCode)
        .map((p) => ({ id: String(p.id), name: p.name, unit: p.unit, category: p.category, isTopping: !!p.isTopping })),
    [products, storeCode]
  );

  const sold = useMemo(() => {
    // historyData đã gộp bills + history gần nhất; dayHistory bổ sung các ngày cũ. deduplicateBills xử lý trùng.
    const bills = [...historyData.filter((b) => !b.storeCode || b.storeCode === storeCode), ...dayHistory];
    return soldQtyByProduct(bills, storeProducts, date, storeCode, startMinute);
  }, [historyData, dayHistory, storeProducts, date, storeCode, startMinute]);

  // Bản ghi đang hiển thị = phiếu đã lưu + nháp đang nhập (để bảng đối chiếu cập nhật tức thì)
  const effectiveRecord: DailyStockRecord = useMemo(() => {
    const lines = { ...(record?.lines || {}) };
    for (const [key, d] of Object.entries(draft)) {
      const base = lines[key] || { productId: key, name: key };
      lines[key] = {
        ...base,
        ...(d.opening !== undefined ? { opening: parseQty(d.opening) } : {}),
        ...(d.received !== undefined ? { received: parseQty(d.received) } : {}),
        ...(d.closing !== undefined ? { closing: parseQty(d.closing) } : {}),
      };
    }
    return { ...(record || { date }), lines };
  }, [record, draft, date]);

  const tol = parseQty(tolerance) ?? 0;
  const allRows = useMemo(() => {
    const visibleProducts = storeProducts.filter((p) => includeToppings || !p.isTopping);
    return buildVarianceRows(visibleProducts, effectiveRecord, sold, tol);
  }, [storeProducts, includeToppings, effectiveRecord, sold, tol]);

  const categories = useMemo(() => Array.from(new Set(allRows.map((r) => r.category).filter(Boolean))).sort(), [allRows]);

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    return allRows.filter((r) => {
      if (category !== "ALL" && r.category !== category) return false;
      if (q && !r.name.toLowerCase().includes(q)) return false;
      if (onlyCounted && r.status === "EMPTY" && (mode !== "compare" || r.sold === 0)) return false;
      if (mode === "compare" && r.status === "EMPTY" && r.sold === 0) return false;
      return true;
    });
  }, [allRows, category, search, onlyCounted, mode]);

  const summary = useMemo(() => summarizeVariance(allRows), [allRows]);
  const soldNotCounted = useMemo(() => allRows.filter((r) => r.status === "EMPTY" && r.sold > 0).length, [allRows]);

  const locked = record?.locked === true;
  const canEdit = !locked || isManager;
  const dirty = Object.keys(draft).length > 0;
  const today = businessDateOf(nowTs, startMinute);

  const setField = (key: string, field: "opening" | "received" | "closing", value: string) => {
    setDraft((d) => ({ ...d, [key]: { ...d[key], [field]: value } }));
  };

  const fieldValue = (r: VarianceRow, field: "opening" | "received" | "closing") => {
    const d = draft[r.key]?.[field];
    if (d !== undefined) return d;
    const v = r[field];
    return v == null ? "" : String(v);
  };

  const fillFromPrevious = () => {
    const prevOpen = openingFromPrevious(prevRecord);
    const keys = Object.keys(prevOpen);
    if (keys.length === 0) {
      setMessage({ type: "err", text: `Ngày ${previousDate(date)} chưa có tồn cuối để chuyển sang.` });
      return;
    }
    setDraft((d) => {
      const next = { ...d };
      for (const k of keys) next[k] = { ...next[k], opening: String(prevOpen[k]) };
      return next;
    });
    setMessage({ type: "ok", text: `Đã điền tồn đầu cho ${keys.length} món từ tồn cuối ngày ${previousDate(date)}. Kiểm tra lại rồi bấm Lưu.` });
  };

  const save = async () => {
    if (!storeCode || !user || !dirty) return;
    // Kiểm tra số hợp lệ
    for (const [key, d] of Object.entries(draft)) {
      for (const f of ["opening", "received", "closing"] as const) {
        const v = d[f];
        if (v !== undefined && v.trim() !== "" && parseQty(v) == null) {
          const name = allRows.find((r) => r.key === key)?.name || key;
          setMessage({ type: "err", text: `Số lượng không hợp lệ ở món "${name}".` });
          return;
        }
      }
    }
    setSaving(true);
    setMessage(null);
    try {
      const now = Date.now();
      const who = { uid: user.uid || user.id, name: user.fullName || user.username || "" };
      const updates: Record<string, unknown> = {
        date,
        updatedAt: now,
        updatedBy: who.uid,
        updatedByName: who.name,
      };
      let touchedOpening = false;
      let touchedClosing = false;
      for (const [key, d] of Object.entries(draft)) {
        const row = allRows.find((r) => r.key === key);
        updates[`lines/${key}/productId`] = row?.productId || key;
        updates[`lines/${key}/name`] = row?.name || key;
        if (row?.unit) updates[`lines/${key}/unit`] = row.unit;
        if (row?.category) updates[`lines/${key}/category`] = row.category;
        if (d.opening !== undefined) {
          updates[`lines/${key}/opening`] = parseQty(d.opening);
          touchedOpening = true;
        }
        if (d.received !== undefined) {
          updates[`lines/${key}/received`] = parseQty(d.received);
          touchedClosing = true;
        }
        if (d.closing !== undefined) {
          updates[`lines/${key}/closing`] = parseQty(d.closing);
          touchedClosing = true;
        }
      }
      if (touchedOpening) {
        updates.openingSavedAt = now;
        updates.openingSavedBy = who.uid;
        updates.openingSavedByName = who.name;
      }
      if (touchedClosing) {
        updates.closingSavedAt = now;
        updates.closingSavedBy = who.uid;
        updates.closingSavedByName = who.name;
      }
      await update(ref(db, `stores/${storeCode}/daily_stock_counts/${date}`), updates);
      setDraft(() => ({}));
      setMessage({ type: "ok", text: "Đã lưu số liệu kiểm hàng." });
    } catch (e) {
      setMessage({ type: "err", text: `Lưu thất bại: ${errorMessage(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const toggleLock = async () => {
    if (!storeCode || !user || !isManager) return;
    if (dirty) {
      setMessage({ type: "err", text: "Vui lòng lưu số liệu trước khi chốt phiếu." });
      return;
    }
    if (!locked && !confirm(`Chốt phiếu kiểm hàng ngày ${date}? Nhân viên sẽ không sửa được nữa.`)) return;
    setSaving(true);
    try {
      const now = Date.now();
      await update(ref(db, `stores/${storeCode}/daily_stock_counts/${date}`), {
        date,
        locked: !locked,
        lockedAt: now,
        lockedBy: user.uid || user.id,
        lockedByName: user.fullName || user.username || "",
      });
      setMessage({ type: "ok", text: locked ? "Đã mở chốt phiếu." : "Đã chốt phiếu kiểm hàng." });
    } catch (e) {
      setMessage({ type: "err", text: `Không thực hiện được: ${errorMessage(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const exportExcel = () => {
    const data = allRows.filter((r) => r.status !== "EMPTY" || r.sold > 0);
    exportStandardReportExcel({
      reportCode: "KIEMHANG",
      reportTitle: "Đối chiếu tồn đầu / tồn cuối ngày với hàng bán ra",
      storeName: store?.storeName,
      storeAddress: store?.address as string | undefined,
      storePhone: store?.phone as string | undefined,
      storeCode,
      dateRangeText: `Ngày kinh doanh: ${date.split("-").reverse().join("/")}`,
      startDate: date,
      endDate: date,
      headers: ["Tên hàng", "ĐVT", "Nhóm", "Tồn đầu", "Nhập thêm", "Tồn cuối", "Xuất theo kiểm đếm", "Bán (hệ thống)", "Chênh lệch", "Trạng thái"],
      rows: data.map((r) => [
        r.name,
        r.unit,
        r.category,
        r.opening ?? "",
        r.received ?? "",
        r.closing ?? "",
        r.countedOut ?? "",
        r.sold,
        r.variance ?? "",
        r.status === "EMPTY" ? "Chưa kiểm (có bán)" : VARIANCE_STATUS_LABEL[r.status],
      ]),
      totalRow: ["TỔNG", "", "", "", "", "", "", summary.soldQty, "", `Thiếu ${fmtQty(summary.shortQty)} · Dư ${fmtQty(summary.overQty)}`],
      notes: "Chênh lệch = (Tồn đầu + Nhập thêm − Tồn cuối) − Bán theo hệ thống. Dương = thiếu hàng, âm = dư hàng.",
    });
  };

  if (!storeCode) {
    return <div style={{ padding: "24px", color: "var(--subtext)" }}>Chưa xác định được chi nhánh. Vui lòng chọn một chi nhánh cụ thể.</div>;
  }

  const modeBtn = (m: Mode, label: string, Icon: typeof Sunrise) => (
    <button
      key={m}
      onClick={() => setMode(m)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: "6px",
        padding: "8px 14px",
        borderRadius: "10px",
        border: "1px solid " + (mode === m ? "var(--primary)" : "var(--border)"),
        background: mode === m ? "var(--primary)" : "var(--surface)",
        color: mode === m ? "#fff" : "var(--text)",
        fontWeight: 700,
        fontSize: "13px",
        cursor: "pointer",
      }}
    >
      <Icon size={16} /> {label}
    </button>
  );

  return (
    <div style={{ padding: "24px" }}>
      <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "space-between", gap: "16px", marginBottom: "20px" }}>
        <div>
          <h1 style={{ fontSize: "24px", fontWeight: 800, color: "var(--text)", margin: 0, display: "flex", alignItems: "center", gap: "8px" }}>
            <ClipboardCheck size={24} /> Kiểm hàng đầu / cuối ngày
          </h1>
          <p style={{ fontSize: "14px", color: "var(--subtext)", margin: "4px 0 0" }}>
            Nhập tồn đầu ngày, tồn cuối ngày và đối chiếu chênh lệch với hàng hoá bán ra — chi nhánh {store?.storeName || storeCode}
          </p>
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "8px" }}>
          {stores.length > 1 && (
            <select
              value={storeCode}
              onChange={(e) => setCurrentStoreCode(e.target.value)}
              style={controlStyle}
              aria-label="Chi nhánh"
            >
              {stores.map((s) => (
                <option key={s.storeCode} value={s.storeCode}>
                  {s.storeName || s.storeCode}
                </option>
              ))}
            </select>
          )}
          <div style={{ ...controlStyle, display: "flex", alignItems: "center", gap: "6px" }}>
            <Calendar size={16} color="var(--primary)" />
            <input
              type="date"
              value={date}
              max={today}
              onChange={(e) => e.target.value && setDate(e.target.value)}
              style={{ border: "none", outline: "none", background: "transparent", color: "var(--text)", fontWeight: 600 }}
              aria-label="Ngày kinh doanh"
            />
          </div>
          {date !== today && (
            <button onClick={() => setDate(today)} style={btnSecondary}>
              Hôm nay
            </button>
          )}
        </div>
      </div>

      {/* Trạng thái phiếu */}
      <div style={{ display: "flex", flexWrap: "wrap", gap: "8px 20px", fontSize: "13px", color: "var(--subtext)", marginBottom: "16px" }}>
        <span>
          Tồn đầu: {record?.openingSavedAt ? <b style={{ color: "var(--text)" }}>{record.openingSavedByName} lúc {fmtTime(record.openingSavedAt)}</b> : "chưa nhập"}
        </span>
        <span>
          Tồn cuối: {record?.closingSavedAt ? <b style={{ color: "var(--text)" }}>{record.closingSavedByName} lúc {fmtTime(record.closingSavedAt)}</b> : "chưa nhập"}
        </span>
        {locked && (
          <span style={{ color: "#ef4444", fontWeight: 700, display: "flex", alignItems: "center", gap: "4px" }}>
            <Lock size={14} /> Đã chốt bởi {record?.lockedByName} lúc {fmtTime(record?.lockedAt)}
          </span>
        )}
      </div>

      {/* Chế độ */}
      <div style={{ display: "flex", flexWrap: "wrap", gap: "8px", marginBottom: "16px" }}>
        {modeBtn("opening", "Tồn đầu ngày", Sunrise)}
        {modeBtn("closing", "Tồn cuối ngày", Sunset)}
        {modeBtn("compare", "Đối chiếu chênh lệch", Scale)}
      </div>

      {/* Tổng quan */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(150px, 100%), 1fr))", gap: "12px", marginBottom: "16px" }}>
        <StatCard label="Món đã kiểm" value={String(summary.counted)} color="var(--primary)" />
        <StatCard label="Khớp" value={String(summary.match)} color={STATUS_COLOR.MATCH} />
        <StatCard label="Thiếu hàng" value={`${summary.short} món · ${fmtQty(summary.shortQty)}`} color={STATUS_COLOR.SHORT} />
        <StatCard label="Dư hàng" value={`${summary.over} món · ${fmtQty(summary.overQty)}`} color={STATUS_COLOR.OVER} />
        <StatCard label="Chưa đủ số liệu" value={String(summary.incomplete)} color={STATUS_COLOR.INCOMPLETE} />
        <StatCard label="Có bán nhưng chưa kiểm" value={String(soldNotCounted)} color={STATUS_COLOR.EMPTY} />
      </div>

      {/* Bộ lọc + thao tác */}
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "8px", marginBottom: "12px" }}>
        <div style={{ ...controlStyle, display: "flex", alignItems: "center", gap: "6px", flex: "1 1 200px", maxWidth: "320px" }}>
          <Search size={16} color="var(--muted)" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Tìm món..."
            style={{ border: "none", outline: "none", background: "transparent", color: "var(--text)", width: "100%" }}
          />
        </div>
        <select value={category} onChange={(e) => setCategory(e.target.value)} style={controlStyle} aria-label="Nhóm hàng">
          <option value="ALL">Tất cả nhóm</option>
          {categories.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        <label style={checkLabel}>
          <input type="checkbox" checked={includeToppings} onChange={(e) => setIncludeToppings(e.target.checked)} /> Gồm topping
        </label>
        {mode !== "compare" && (
          <label style={checkLabel}>
            <input type="checkbox" checked={onlyCounted} onChange={(e) => setOnlyCounted(e.target.checked)} /> Chỉ món đã kiểm
          </label>
        )}
        {mode === "compare" && (
          <label style={checkLabel}>
            Dung sai ±
            <input
              value={tolerance}
              onChange={(e) => setTolerance(e.target.value)}
              inputMode="decimal"
              style={{ ...inputStyle, width: "60px" }}
              aria-label="Dung sai"
            />
          </label>
        )}
        <div style={{ flex: 1 }} />
        {mode === "opening" && canEdit && (
          <button onClick={fillFromPrevious} style={btnSecondary} title="Lấy tồn cuối của ngày trước làm tồn đầu hôm nay">
            <History size={15} /> Lấy tồn cuối ngày trước
          </button>
        )}
        {mode === "compare" && (
          <button onClick={exportExcel} style={btnSecondary}>
            <Download size={15} /> Xuất Excel
          </button>
        )}
        {isManager && mode === "compare" && (
          <button onClick={toggleLock} disabled={saving} style={btnSecondary}>
            {locked ? <Unlock size={15} /> : <Lock size={15} />} {locked ? "Mở chốt" : "Chốt phiếu"}
          </button>
        )}
        {mode !== "compare" && canEdit && (
          <button onClick={save} disabled={!dirty || saving} style={{ ...btnPrimary, opacity: !dirty || saving ? 0.6 : 1 }}>
            <Save size={15} /> {saving ? "Đang lưu..." : "Lưu"}
          </button>
        )}
      </div>

      {message && (
        <div
          style={{
            padding: "10px 14px",
            borderRadius: "10px",
            marginBottom: "12px",
            fontSize: "13px",
            fontWeight: 600,
            background: message.type === "ok" ? "#10b98115" : "#ef444415",
            color: message.type === "ok" ? "#047857" : "#b91c1c",
          }}
        >
          {message.text}
        </div>
      )}
      {locked && !isManager && (
        <div style={{ padding: "10px 14px", borderRadius: "10px", marginBottom: "12px", fontSize: "13px", background: "#ef444415", color: "#b91c1c" }}>
          Phiếu ngày này đã được chốt — chỉ Chủ quán / Quản lý mới sửa được.
        </div>
      )}

      {loading ? (
        <div style={{ padding: "40px", textAlign: "center", color: "var(--muted)" }}>Đang tải phiếu kiểm hàng...</div>
      ) : (
        <div style={{ background: "var(--surface)", borderRadius: "12px", border: "1px solid var(--border)", overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", minWidth: mode === "compare" ? "860px" : "520px" }}>
            <thead style={{ background: "var(--surface-muted)", borderBottom: "2px solid var(--border)" }}>
              <tr>
                <th style={thStyle}>Tên hàng</th>
                <th style={thStyle}>ĐVT</th>
                {mode === "opening" && <th style={thNum}>Tồn đầu ngày</th>}
                {mode === "closing" && (
                  <>
                    <th style={thNum}>Tồn đầu</th>
                    <th style={thNum}>Nhập thêm</th>
                    <th style={thNum}>Tồn cuối ngày</th>
                    <th style={thNum}>Đã bán</th>
                  </>
                )}
                {mode === "compare" && (
                  <>
                    <th style={thNum}>Tồn đầu</th>
                    <th style={thNum}>Nhập thêm</th>
                    <th style={thNum}>Tồn cuối</th>
                    <th style={thNum} title="Tồn đầu + Nhập thêm − Tồn cuối">Xuất (kiểm đếm)</th>
                    <th style={thNum}>Bán (hệ thống)</th>
                    <th style={thNum} title="Xuất kiểm đếm − Bán hệ thống">Chênh lệch</th>
                    <th style={thStyle}>Trạng thái</th>
                  </>
                )}
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr>
                  <td colSpan={9} style={{ ...tdStyle, textAlign: "center", color: "var(--muted)", padding: "28px" }}>
                    {mode === "compare" ? "Chưa có số liệu kiểm hàng hoặc hàng bán trong ngày này." : "Không có món phù hợp."}
                  </td>
                </tr>
              ) : (
                rows.map((r) => (
                  <tr key={r.key} style={{ borderBottom: "1px solid var(--border)" }}>
                    <td style={{ ...tdStyle, fontWeight: 600 }}>
                      {r.name}
                      {r.category && <div style={{ fontSize: "11px", color: "var(--muted)", fontWeight: 400 }}>{r.category}</div>}
                    </td>
                    <td style={tdStyle}>{r.unit || "—"}</td>
                    {mode === "opening" && (
                      <td style={tdNum}>
                        <QtyInput value={fieldValue(r, "opening")} disabled={!canEdit} onChange={(v) => setField(r.key, "opening", v)} />
                      </td>
                    )}
                    {mode === "closing" && (
                      <>
                        <td style={tdNum}>{fmtQty(r.opening)}</td>
                        <td style={tdNum}>
                          <QtyInput value={fieldValue(r, "received")} disabled={!canEdit} onChange={(v) => setField(r.key, "received", v)} />
                        </td>
                        <td style={tdNum}>
                          <QtyInput value={fieldValue(r, "closing")} disabled={!canEdit} onChange={(v) => setField(r.key, "closing", v)} />
                        </td>
                        <td style={tdNum}>{fmtQty(r.sold)}</td>
                      </>
                    )}
                    {mode === "compare" && (
                      <>
                        <td style={tdNum}>{fmtQty(r.opening)}</td>
                        <td style={tdNum}>{fmtQty(r.received)}</td>
                        <td style={tdNum}>{fmtQty(r.closing)}</td>
                        <td style={tdNum}>{fmtQty(r.countedOut)}</td>
                        <td style={tdNum}>{fmtQty(r.sold)}</td>
                        <td style={{ ...tdNum, fontWeight: 800, color: STATUS_COLOR[r.status] }}>
                          {r.variance == null ? "—" : `${r.variance > 0 ? "+" : ""}${fmtQty(r.variance)}`}
                        </td>
                        <td style={tdStyle}>
                          <span style={badge(STATUS_COLOR[r.status])}>
                            {r.status === "EMPTY" ? "Chưa kiểm (có bán)" : VARIANCE_STATUS_LABEL[r.status]}
                          </span>
                        </td>
                      </>
                    )}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      <p style={{ fontSize: "12px", color: "var(--muted)", marginTop: "12px", lineHeight: 1.6 }}>
        Xuất theo kiểm đếm = Tồn đầu + Nhập thêm − Tồn cuối. Bán theo hệ thống lấy từ hóa đơn đã thanh toán trong ngày kinh doanh
        (POS & Web). Chênh lệch dương = <b style={{ color: STATUS_COLOR.SHORT }}>thiếu hàng</b> (hao hụt, bán không lên bill...), âm ={" "}
        <b style={{ color: STATUS_COLOR.OVER }}>dư hàng</b>. Phiếu đã chốt chỉ Chủ quán / Quản lý mới sửa được.
      </p>
    </div>
  );
}

function QtyInput({ value, onChange, disabled }: { value: string; onChange: (v: string) => void; disabled?: boolean }) {
  const invalid = value.trim() !== "" && parseQty(value) == null;
  return (
    <input
      value={value}
      onChange={(e) => onChange(e.target.value)}
      disabled={disabled}
      inputMode="decimal"
      placeholder="—"
      style={{ ...inputStyle, width: "90px", textAlign: "right", borderColor: invalid ? "#ef4444" : "var(--border)" }}
    />
  );
}

function StatCard({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div style={{ background: "var(--surface)", padding: "14px 16px", borderRadius: "12px", border: "1px solid var(--border)", borderLeft: `4px solid ${color}` }}>
      <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: 600 }}>{label}</div>
      <div style={{ fontSize: "18px", fontWeight: 800, color: "var(--text)", marginTop: "4px" }}>{value}</div>
    </div>
  );
}

const controlStyle: React.CSSProperties = {
  background: "var(--surface)",
  border: "1px solid var(--border)",
  borderRadius: "10px",
  padding: "7px 12px",
  fontSize: "13px",
  color: "var(--text)",
};
const inputStyle: React.CSSProperties = {
  padding: "6px 8px",
  border: "1px solid var(--border)",
  borderRadius: "8px",
  fontSize: "14px",
  background: "var(--bg)",
  color: "var(--text)",
  outline: "none",
};
const checkLabel: React.CSSProperties = { display: "flex", alignItems: "center", gap: "6px", fontSize: "13px", color: "var(--text)" };
const btnBase: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: "6px",
  padding: "8px 14px",
  borderRadius: "10px",
  fontSize: "13px",
  fontWeight: 700,
  cursor: "pointer",
};
const btnPrimary: React.CSSProperties = { ...btnBase, background: "var(--primary)", color: "#fff", border: "none" };
const btnSecondary: React.CSSProperties = { ...btnBase, background: "var(--surface)", color: "var(--text)", border: "1px solid var(--border)" };
const thStyle: React.CSSProperties = {
  padding: "10px 12px",
  textAlign: "left",
  fontSize: "12px",
  fontWeight: 700,
  color: "var(--subtext)",
  textTransform: "uppercase",
  whiteSpace: "nowrap",
};
const thNum: React.CSSProperties = { ...thStyle, textAlign: "right" };
const tdStyle: React.CSSProperties = { padding: "8px 12px", fontSize: "13px", color: "var(--text)" };
const tdNum: React.CSSProperties = { ...tdStyle, textAlign: "right", whiteSpace: "nowrap" };
const badge = (color: string): React.CSSProperties => ({
  display: "inline-block",
  padding: "2px 8px",
  borderRadius: "6px",
  fontSize: "11px",
  fontWeight: 700,
  background: `${color}18`,
  color,
  whiteSpace: "nowrap",
});
