import { useState } from "react";
import { Mail, MoreHorizontal, Plus, Settings, Trash2, Search } from "lucide-react";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

const TEAM_MEMBERS = [
  {
    id: 1,
    name: "Unified Dev",
    email: "maintainer@akira.app",
    role: "Admin",
    roleColor: "purple",
    status: "online",
    initials: "AM",
  },
  {
    id: 2,
    name: "Sync Agent",
    email: "sync@akira.app",
    role: "Operator",
    roleColor: "blue",
    status: "busy",
    initials: "SA",
  },
  {
    id: 3,
    name: "Config Service",
    email: "config@akira.app",
    role: "Service",
    roleColor: "emerald",
    status: "offline",
    initials: "CS",
  },
  {
    id: 4,
    name: "Security Monitor",
    email: "security@akira.app",
    role: "Security",
    roleColor: "zinc",
    status: "online",
    initials: "SM",
  },
];

export function TeamView() {
  const [searchTerm, setSearchTerm] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const itemsPerPage = 5;

  const filteredMembers = TEAM_MEMBERS.filter(
    (member) =>
      member.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      member.email.toLowerCase().includes(searchTerm.toLowerCase()),
  );

  const totalPages = Math.ceil(filteredMembers.length / itemsPerPage);
  const currentData = filteredMembers.slice((currentPage - 1) * itemsPerPage, currentPage * itemsPerPage);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div className="relative w-full md:w-96">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-400" />
          <Input
            placeholder="Pesquisar membro..."
            className="pl-10 bg-white dark:bg-zinc-900 border-none focus-visible:ring-0"
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
          />
        </div>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between border-b border-zinc-100 p-6 dark:border-zinc-800">
          <div className="space-y-1">
            <CardTitle className="text-lg font-bold">Membros da Equipa</CardTitle>
            <p className="text-sm text-zinc-500">Total: {TEAM_MEMBERS.length} membros</p>
          </div>

          <Dialog open={isAddModalOpen} onOpenChange={setIsAddModalOpen}>
            <DialogTrigger asChild>
              <Button size="icon" className="h-10 w-10 rounded-full bg-purple-600 hover:bg-purple-700 text-white shadow-lg shadow-purple-600/20 dark:bg-white dark:text-purple-700 dark:hover:bg-zinc-100">
                <Plus className="h-5 w-5" />
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-[425px]">
              <DialogHeader>
                <DialogTitle>Adicionar Novo Membro</DialogTitle>
              </DialogHeader>
              <div className="grid gap-4 py-4">
                <div className="grid gap-2">
                  <Label htmlFor="name">Nome Completo</Label>
                  <Input id="name" placeholder="Ex: Ana Silva" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="email">Email Profissional</Label>
                  <Input id="email" placeholder="nome@akira.app" type="email" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="role">Função</Label>
                  <Select>
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione a função" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="admin">Admin</SelectItem>
                      <SelectItem value="operator">Operator</SelectItem>
                      <SelectItem value="service">Service</SelectItem>
                      <SelectItem value="security">Security</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <DialogFooter>
                <Button variant="ghost" onClick={() => setIsAddModalOpen(false)}>
                  Cancelar
                </Button>
                <Button onClick={() => setIsAddModalOpen(false)}>Adicionar Membro</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </CardHeader>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow className="bg-zinc-50/50 hover:bg-zinc-50/50 dark:bg-transparent dark:hover:bg-transparent border-zinc-100 dark:border-zinc-800">
                <TableHead className="pl-6 w-[300px] text-xs font-bold uppercase tracking-wider text-muted-foreground">
                  Membro
                </TableHead>
                <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Função</TableHead>
                <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Estado</TableHead>
                <TableHead className="pr-6 text-right text-xs font-bold uppercase tracking-wider text-muted-foreground">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {currentData.map((member) => (
                <TableRow key={member.id} className="border-zinc-100 hover:bg-zinc-50/50 dark:border-zinc-800 dark:hover:bg-zinc-800/50">
                  <TableCell className="pl-6 py-4">
                    <div className="flex items-center gap-3">
                      <Avatar className="h-9 w-9 border border-zinc-200 dark:border-zinc-700">
                        <AvatarFallback className="bg-zinc-100 dark:bg-zinc-800 text-xs font-medium text-zinc-900 dark:text-zinc-300">
                          {member.initials}
                        </AvatarFallback>
                      </Avatar>
                      <div className="flex flex-col">
                        <span className="text-sm font-semibold text-foreground">{member.name}</span>
                        <span className="text-xs text-muted-foreground">{member.email}</span>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant="outline"
                      className={`font-medium rounded-full px-2.5 py-0.5 border ${member.roleColor === "purple"
                          ? "bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-500/10 dark:text-purple-400 dark:border-purple-500/20"
                          : member.roleColor === "blue"
                            ? "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-500/10 dark:text-blue-400 dark:border-blue-500/20"
                            : member.roleColor === "emerald"
                              ? "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-400 dark:border-emerald-500/20"
                              : "bg-zinc-100 text-zinc-700 border-zinc-200 dark:bg-zinc-800 dark:text-zinc-400 dark:border-zinc-700"}`}
                    >
                      {member.role}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span className="relative flex h-2.5 w-2.5">
                        <span
                          className={`animate-ping absolute inline-flex h-full w-full rounded-full opacity-75 ${member.status === "online" ? "bg-emerald-400" : member.status === "busy" ? "bg-amber-400" : "bg-zinc-400 hidden"}`}
                        />
                        <span
                          className={`relative inline-flex rounded-full h-2.5 w-2.5 ${member.status === "online" ? "bg-emerald-500" : member.status === "busy" ? "bg-amber-500" : "bg-zinc-400"}`}
                        />
                      </span>
                      <span className="text-sm text-zinc-600 dark:text-zinc-400 capitalize">
                        {member.status === "online" ? "Online" : member.status === "busy" ? "Ocupado" : "Offline"}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell className="pr-6 text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground hover:text-foreground">
                          <MoreHorizontal size={16} />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-[160px]">
                        <DropdownMenuItem className="gap-2">
                          <Settings size={14} /> Editar
                        </DropdownMenuItem>
                        <DropdownMenuItem className="gap-2">
                          <Mail size={14} /> Enviar Email
                        </DropdownMenuItem>
                        <DropdownMenuItem className="gap-2 text-red-600 dark:text-red-400 focus:text-red-600 dark:focus:text-red-400">
                          <Trash2 size={14} /> Remover
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>

        {totalPages > 1 && (
          <div className="flex items-center justify-between border-t border-zinc-100 p-4 dark:border-zinc-800">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setCurrentPage(currentPage - 1)}
              disabled={currentPage === 1}
              className="gap-1 rounded-lg border-zinc-200 bg-white text-zinc-700 hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-300 dark:hover:bg-zinc-800"
            >
              Anterior
            </Button>

            <span className="text-xs font-medium text-zinc-500 dark:text-zinc-500">
              Página {currentPage} de {totalPages}
            </span>

            <Button
              variant="outline"
              size="sm"
              onClick={() => setCurrentPage(currentPage + 1)}
              disabled={currentPage === totalPages}
              className="gap-1 rounded-lg border-zinc-200 bg-white text-zinc-700 hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-300 dark:hover:bg-zinc-800"
            >
              Seguinte
            </Button>
          </div>
        )}
      </Card>
    </div>
  );
}
