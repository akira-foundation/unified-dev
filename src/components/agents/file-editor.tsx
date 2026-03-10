import { X, ExternalLink } from "lucide-react";
import { useAgentsStore } from "@/stores/useAgentsStore";

export function FileEditor() {
  const { selectedFilePath, setSelectedFilePath } = useAgentsStore();

  if (!selectedFilePath) return null;

  const mockContent = `<?php

declare(strict_types=1);

namespace App\\Actions\\OnlineSale;

use App\\Actions\\SearchTransactionTicketsAction;
use App\\Mail\\OnlineSale\\TicketAccessCodeMail;
use Illuminate\\Support\\Facades\\Mail;
use Illuminate\\Support\\Facades\\URL;

final readonly class RequestTicketAccessAction
{
    public function __construct(
        private SearchTransactionTicketsAction $searchAction,
    ) {}

    public function handle(string $reference, string $email): bool
    {
        $tickets = $this->searchAction->handle($reference, $email);

        if ($tickets->isEmpty()) {
            return false;
        }

        $locale = $tickets->first()?->sispTransaction?->locale ?? 'en';

        $code = (string) random_int(100000, 999999);
        $cacheKey = 'ticket_access:' . hash('sha256', $reference . ':' . $email);

        $token = str()->random(64);

        cache()->put($cacheKey, $code, now()->addMinutes(5));
        cache()->put('ticket_access_token:' . $token, ['reference' => $reference, 'email' => $email], now()->addMinutes(5));

        $signedUrl = URL::temporarySignedRoute(
            'online-sale.my-tickets.verify-access-link',
            now()->addMinutes(5),
            ['token' => $token],
        );

        Mail::to($email)->send(new TicketAccessCodeMail(
            code: $code,
            reference: $reference,
            signedUrl: $signedUrl,
            locale: $locale,
        ));

        return true;
    }
}`;

  return (
    <div className="flex flex-col h-full bg-[#0A0A0A] border-r border-white/[0.03]">
      {/* Editor Header */}
      <div className="h-10 border-b border-white/[0.03] flex items-center justify-between px-4 bg-[#0D0D0D]">
        <div className="flex items-center gap-2 overflow-hidden">
          <span className="text-[10px] text-zinc-500 font-mono truncate">{selectedFilePath}</span>
          <button className="p-1 hover:bg-white/5 rounded text-zinc-500">
            <ExternalLink className="h-3 w-3" />
          </button>
        </div>
        <button
          onClick={() => setSelectedFilePath(null)}
          className="p-1 hover:bg-red-500/10 hover:text-red-500 rounded text-zinc-500 transition-colors"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Editor Content */}
      <div className="flex-1 overflow-auto p-6 font-mono text-[13px] leading-relaxed custom-scrollbar">
        <pre className="text-zinc-400">
          {mockContent.split('\n').map((line, i) => (
            <div key={i} className="flex gap-6 group">
              <span className="w-8 text-right text-zinc-700 select-none group-hover:text-zinc-500">{i + 1}</span>
              <span className={line.includes('class') || line.includes('function') ? 'text-zinc-200' : 'text-zinc-500'}>
                {line}
              </span>
            </div>
          ))}
        </pre>
      </div>
    </div>
  );
}
