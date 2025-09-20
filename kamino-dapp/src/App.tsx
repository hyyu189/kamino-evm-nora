import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { SidebarProvider } from "@/components/ui/sidebar";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import NotFound from "./pages/NotFound";
import { VaultPage } from "./pages/VaultPage";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const App = () => (
  <TooltipProvider>
    <Toaster />
    <Sonner />
    <BrowserRouter>
      <SidebarProvider>
        <div className="flex min-h-screen w-full">
          <div className="flex-1 flex flex-col">
            <header className="flex h-16 items-center justify-between border-b bg-background px-6">
              <h1 className="text-xl font-semibold">Kamino DApp</h1>
              <ConnectButton />
            </header>
            <main className="flex-1 p-6 bg-background">
              <Routes>
                <Route path="/" element={<VaultPage />} />
                {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
                <Route path="*" element={<NotFound />} />
              </Routes>
            </main>
          </div>
        </div>
      </SidebarProvider>
    </BrowserRouter>
  </TooltipProvider>
);

export default App;