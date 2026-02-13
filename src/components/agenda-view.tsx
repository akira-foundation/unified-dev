import { AlertCircle, Briefcase, ChevronRight, Clock, Scale } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
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
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-semibold text-foreground">Próximos Syncs & Eventos</h3>
          <Button variant="ghost" className="text-xs h-8 text-muted-foreground hover:text-foreground">
            Ver Calendário Completo
          </Button>
        </div>

        <Card>
          <div className="divide-y divide-zinc-100 dark:divide-zinc-800">
            {AGENDA_ITEMS.map((item) => (
              <div
                key={item.id}
                className="flex items-center gap-4 p-5 hover:bg-zinc-50/50 dark:hover:bg-zinc-800/50 transition-colors group cursor-pointer"
              >
                <div
                  className={cn(
                    "flex h-12 w-12 shrink-0 flex-col items-center justify-center rounded-lg text-[10px] font-bold uppercase tracking-wider",
                    item.dateBadge.class,
                  )}
                >
                  {item.dateBadge.label}
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <h4 className="font-semibold text-foreground truncate">{item.title}</h4>
                    {item.urgency && (
                      <Badge
                        variant="outline"
                        className="border-red-200 bg-red-50 text-[10px] text-red-600 dark:border-red-900/50 dark:bg-red-900/20 dark:text-red-400"
                      >
                        {item.urgency}
                      </Badge>
                    )}
                  </div>

                  <p className="text-sm text-muted-foreground truncate">{item.subtitle}</p>
                </div>

                <div className="hidden sm:flex flex-col items-end gap-1 text-xs text-muted-foreground">
                  <div className="flex items-center gap-1.5 font-medium">
                    <Clock size={13} /> {item.time}
                  </div>
                  <div className="flex items-center gap-1.5 uppercase tracking-wide opacity-70">
                    {item.type === "MEETING" && <Briefcase size={13} />}
                    {item.type === "SYNC" && <Scale size={13} />}
                    {item.type === "DEADLINE" && <AlertCircle size={13} />}
                    {item.type}
                  </div>
                </div>

                <ChevronRight className="h-4 w-4 text-zinc-300 dark:text-zinc-600 group-hover:text-zinc-500 transition-colors" />
              </div>
            ))}
          </div>
        </Card>
      </div>

      <div className="space-y-6">
        <Card>
          <div className="p-6">
            <div className="flex items-center justify-between mb-6">
              <div>
                <h2 className="text-lg font-bold text-foreground">Resumo Semanal</h2>
                <p className="text-sm text-muted-foreground">4 a 10 de Novembro</p>
              </div>
            </div>

            <div className="space-y-6">
              <div>
                <div className="flex justify-between items-end mb-2">
                  <span className="text-sm font-medium text-foreground">Syncs</span>
                  <span className="text-lg font-bold text-foreground">3</span>
                </div>
                <div className="h-2 w-full rounded-full bg-zinc-100 dark:bg-zinc-800">
                  <div className="h-full w-3/4 rounded-full bg-purple-600 dark:bg-purple-500" />
                </div>
              </div>

              <div>
                <div className="flex justify-between items-end mb-2">
                  <span className="text-sm font-medium text-foreground">Alertas</span>
                  <span className="text-lg font-bold text-foreground">1</span>
                </div>
                <div className="h-2 w-full rounded-full bg-zinc-100 dark:bg-zinc-800">
                  <div className="h-full w-1/4 rounded-full bg-red-500" />
                </div>
              </div>

              <div>
                <div className="flex justify-between items-end mb-2">
                  <span className="text-sm font-medium text-foreground">Repos Monitorados</span>
                  <span className="text-lg font-bold text-foreground">5</span>
                </div>
                <div className="h-2 w-full rounded-full bg-zinc-100 dark:bg-zinc-800">
                  <div className="h-full w-1/2 rounded-full bg-blue-500" />
                </div>
              </div>
            </div>

            <div className="mt-8 pt-6 border-t border-zinc-100 dark:border-zinc-800">
              <Button className="w-full bg-zinc-900 text-white hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200">
                Ver Agenda Completa
              </Button>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}
