import { AlertCircle, Briefcase, ChevronRight, Clock, Scale } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface AgendaItem {
  id: string;
  title: string;
  subtitle: string;
  time: string;
  type: "DEADLINE" | "MEETING" | "SYNC";
  dateBadge: {
    label: string;
    class: string;
  };
  urgency?: "URGENTE";
}

const AGENDA_ITEMS: AgendaItem[] = [
  {
    id: "1",
    title: "Janela de sync",
    subtitle: "Org akira-labs",
    time: "17:00",
    type: "SYNC",
    dateBadge: {
      label: "HOJE",
      class: "bg-red-50 text-red-600 dark:bg-red-900/20 dark:text-red-400",
    },
    urgency: "URGENTE",
  },
  {
    id: "2",
    title: "Rotação de token",
    subtitle: "Org akira",
    time: "10:00",
    type: "MEETING",
    dateBadge: {
      label: "AMANHÃ",
      class: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400",
    },
  },
  {
    id: "3",
    title: "Auditoria de repositórios",
    subtitle: "Equipa Segurança",
    time: "09:30",
    type: "DEADLINE",
    dateBadge: {
      label: "15 NOV",
      class: "bg-orange-50 text-orange-600 dark:bg-orange-900/20 dark:text-orange-400",
    },
    urgency: "URGENTE",
  },
];

export function AgendaView() {
  return (
    <div className="grid grid-cols-1 gap-8 lg:grid-cols-3">
      <div className="lg:col-span-2 space-y-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <div className="space-y-1">
              <CardTitle className="text-sm font-bold uppercase tracking-[0.15em]">
                Próximos Syncs & Eventos
              </CardTitle>
              <CardDescription className="text-[10px] font-bold uppercase tracking-widest text-zinc-500/80">
                Prazos e reuniões agendadas
              </CardDescription>
            </div>
            <Button variant="ghost" size="sm" className="text-[10px] font-bold uppercase tracking-widest h-8 px-3">
              Ver Calendário Completo
            </Button>
          </CardHeader>
          <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50">
            <div className="divide-y divide-zinc-100 dark:divide-zinc-800/50">
              {AGENDA_ITEMS.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center gap-4 px-6 py-4 hover:bg-zinc-50/50 dark:hover:bg-zinc-900/10 transition-colors group cursor-pointer"
                >
                  <div
                    className={cn(
                      "flex h-12 w-12 shrink-0 flex-col items-center justify-center rounded-xl text-[10px] font-bold uppercase tracking-wider shadow-sm border border-zinc-100 dark:border-zinc-800/50",
                      item.dateBadge.class,
                    )}
                  >
                    {item.dateBadge.label}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-0.5">
                      <h4 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100 truncate">{item.title}</h4>
                      {item.urgency && (
                        <Badge
                          variant="outline"
                          className="border-red-200 bg-red-50 text-[9px] font-black uppercase tracking-[0.1em] text-red-600 dark:border-red-900/50 dark:bg-red-900/30 dark:text-red-400 py-0"
                        >
                          {item.urgency}
                        </Badge>
                      )}
                    </div>

                    <p className="text-xs text-zinc-500 dark:text-zinc-400 truncate">{item.subtitle}</p>
                  </div>

                  <div className="hidden sm:flex flex-col items-end gap-1 text-[11px] font-medium text-zinc-400 dark:text-zinc-600">
                    <div className="flex items-center gap-1.5">
                      <Clock size={12} className="opacity-70" /> {item.time}
                    </div>
                    <div className="flex items-center gap-1.5 uppercase tracking-widest text-[9px] font-bold opacity-60">
                      {item.type === "MEETING" && <Briefcase size={12} />}
                      {item.type === "SYNC" && <Scale size={12} />}
                      {item.type === "DEADLINE" && <AlertCircle size={12} />}
                      {item.type}
                    </div>
                  </div>

                  <ChevronRight className="h-4 w-4 text-zinc-300 dark:text-zinc-600 group-hover:text-zinc-500 group-hover:translate-x-0.5 transition-all" />
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-bold uppercase tracking-[0.15em]">
              Resumo Semanal
            </CardTitle>
            <CardDescription className="text-[10px] font-bold uppercase tracking-widest text-zinc-500/80">
              4 a 10 de Novembro
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6 p-6 pt-6">
            <div className="space-y-6">
              <div>
                <div className="flex justify-between items-end mb-2">
                  <span className="text-[11px] font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-500">Syncs</span>
                  <span className="text-lg font-black text-zinc-900 dark:text-white leading-none">3</span>
                </div>
                <div className="h-1.5 w-full rounded-full bg-zinc-100 dark:bg-zinc-800/50">
                  <div className="h-full w-3/4 rounded-full bg-purple-500 dark:bg-purple-500/80 shadow-[0_0_12px_rgba(168,85,247,0.4)]" />
                </div>
              </div>

              <div>
                <div className="flex justify-between items-end mb-2">
                  <span className="text-[11px] font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-500">Alertas</span>
                  <span className="text-lg font-black text-zinc-900 dark:text-white leading-none">1</span>
                </div>
                <div className="h-1.5 w-full rounded-full bg-zinc-100 dark:bg-zinc-800/50">
                  <div className="h-full w-1/4 rounded-full bg-red-500 dark:bg-red-500/80 shadow-[0_0_12px_rgba(239,68,68,0.4)]" />
                </div>
              </div>

              <div>
                <div className="flex justify-between items-end mb-2">
                  <span className="text-[11px] font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-500">Repos Monitorados</span>
                  <span className="text-lg font-black text-zinc-900 dark:text-white leading-none">5</span>
                </div>
                <div className="h-1.5 w-full rounded-full bg-zinc-100 dark:bg-zinc-800/50">
                  <div className="h-full w-1/2 rounded-full bg-blue-500 dark:bg-blue-500/80 shadow-[0_0_12px_rgba(59,130,246,0.4)]" />
                </div>
              </div>
            </div>

            <div className="mt-8 pt-6 border-t border-zinc-100 dark:border-zinc-800/50">
              <Button className="w-full h-10 rounded-xl bg-zinc-900 text-white font-bold text-xs uppercase tracking-widest hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200 transition-all active:scale-[0.98]">
                Ver Agenda Completa
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
  );
}
