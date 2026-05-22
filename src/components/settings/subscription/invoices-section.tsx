import { openUrl } from "@tauri-apps/plugin-opener";
import { useI18n } from "@/i18n/i18n";
import { InvoiceDto } from "./subscription-types";

interface InvoicesSectionProps {
  invoices: InvoiceDto[];
  loading: boolean;
  error: string | null;
  hasMore: boolean;
  onLoadMore: () => void;
}

export function InvoicesSection({ invoices, loading, error, hasMore, onLoadMore }: InvoicesSectionProps) {
  const { t } = useI18n();

  return (
    <div className="px-4 py-4 border-t border-zinc-100 dark:border-zinc-800/50">
      <p className="text-[12px] font-semibold text-zinc-500 dark:text-zinc-400 mb-3">
        {t("settings.subscription.invoices.title")}
      </p>

      {loading && (
        <p className="text-[11px] text-zinc-500">{t("settings.subscription.invoices.loading")}</p>
      )}

      {error && (
        <p className="text-[11px] text-red-500">{error}</p>
      )}

      {!loading && !error && invoices.length === 0 && (
        <p className="text-[11px] text-zinc-500">{t("settings.subscription.invoices.empty")}</p>
      )}

      {invoices.length > 0 && (
        <div className="flex flex-col gap-1.5">
          {invoices.map((inv) => {
            const amount = (inv.amount / 100).toLocaleString(undefined, {
              style: "currency",
              currency: inv.currency.toUpperCase(),
            });
            const date = new Date(inv.date).toLocaleDateString();
            const label = inv.number ?? date;

            return (
              <div key={inv.id} className="flex items-center justify-between gap-3 py-1.5 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
                <div className="flex flex-col gap-0.5 min-w-0">
                  <span className="text-[12px] text-zinc-300 truncate">{label}</span>
                  <span className="text-[11px] text-zinc-500">{date} · {amount}</span>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  {inv.pdfUrl && (
                    <button
                      onClick={() => void openUrl(inv.pdfUrl!)}
                      className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
                    >
                      {t("settings.subscription.invoices.download")}
                    </button>
                  )}
                  {inv.hostedUrl && (
                    <button
                      onClick={() => void openUrl(inv.hostedUrl!)}
                      className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
                    >
                      {t("settings.subscription.invoices.view")}
                    </button>
                  )}
                </div>
              </div>
            );
          })}

          {hasMore && (
            <button
              onClick={onLoadMore}
              disabled={loading}
              className="mt-1 text-[11px] text-zinc-400 hover:text-zinc-200 transition-colors disabled:opacity-50 text-left"
            >
              {loading ? t("settings.subscription.invoices.loading") : t("settings.subscription.invoices.load_more")}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
