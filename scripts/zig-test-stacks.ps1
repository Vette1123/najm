<#
Print every thread stack of a running process, named from its PDB, without a
debugger: for a Zig test binary that seems hung. Run it two or three times a few
seconds apart; a frame that moves is slow work, one that never moves is a wait.
  pwsh scripts/zig-test-stacks.ps1 -ProcessId (Get-Process ghostty-test).Id
Limits: x64 only; frames come from StackWalk64, so an inlined function shows as
its caller; it suspends each thread briefly while it walks it.
#>
param([Parameter(Mandatory)][int]$ProcessId, [int]$MaxFrames = 40)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class StackDump {
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenThread(uint access, bool inherit, uint tid);
    [DllImport("kernel32")] static extern uint SuspendThread(IntPtr h);
    [DllImport("kernel32")] static extern uint ResumeThread(IntPtr h);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError=true)] static extern bool GetThreadContext(IntPtr h, IntPtr ctx);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32")] static extern bool Thread32First(IntPtr snap, ref THREADENTRY32 te);
    [DllImport("kernel32")] static extern bool Thread32Next(IntPtr snap, ref THREADENTRY32 te);
    [StructLayout(LayoutKind.Sequential)] struct THREADENTRY32 { public uint dwSize, cntUsage, th32ThreadID, th32OwnerProcessID; public int tpBasePri, tpDeltaPri; public uint dwFlags; }

    [DllImport("dbghelp", SetLastError=true)] static extern uint SymSetOptions(uint o);
    [DllImport("dbghelp", SetLastError=true, CharSet=CharSet.Ansi)] static extern bool SymInitialize(IntPtr p, string path, bool invade);
    [DllImport("dbghelp")] static extern bool SymCleanup(IntPtr p);
    [DllImport("dbghelp")] static extern IntPtr SymFunctionTableAccess64(IntPtr p, ulong addr);
    [DllImport("dbghelp")] static extern ulong SymGetModuleBase64(IntPtr p, ulong addr);
    [DllImport("dbghelp", SetLastError=true)] static extern bool SymFromAddr(IntPtr p, ulong addr, out ulong disp, IntPtr sym);
    delegate IntPtr FtaFn(IntPtr p, ulong a);
    delegate ulong ModBaseFn(IntPtr p, ulong a);
    [DllImport("dbghelp", SetLastError=true)] static extern bool StackWalk64(uint machine, IntPtr proc, IntPtr thread, IntPtr frame, IntPtr ctx, IntPtr readMem, FtaFn fta, ModBaseFn modBase, IntPtr translate);

    public static string Dump(int pid, string symPath, int maxFrames) {
        var sb = new StringBuilder();
        IntPtr proc = OpenProcess(0x1F0FFF, false, pid);
        if (proc == IntPtr.Zero) return "OpenProcess failed " + Marshal.GetLastWin32Error();
        SymSetOptions(0x2 | 0x4 | 0x10); // UNDNAME | DEFERRED_LOADS | LOAD_LINES
        if (!SymInitialize(proc, symPath, true)) sb.AppendLine("SymInitialize failed " + Marshal.GetLastWin32Error());
        FtaFn fta = (p, a) => SymFunctionTableAccess64(p, a);
        ModBaseFn mb = (p, a) => SymGetModuleBase64(p, a);
        var tids = new List<uint>();
        IntPtr snap = CreateToolhelp32Snapshot(0x4, 0);
        var te = new THREADENTRY32(); te.dwSize = (uint)Marshal.SizeOf(typeof(THREADENTRY32));
        if (Thread32First(snap, ref te)) do { if (te.th32OwnerProcessID == pid) tids.Add(te.th32ThreadID); } while (Thread32Next(snap, ref te));
        CloseHandle(snap);
        IntPtr ctxRaw = Marshal.AllocHGlobal(1232 + 16);
        IntPtr ctx = new IntPtr((ctxRaw.ToInt64() + 15) & ~15L);
        IntPtr frame = Marshal.AllocHGlobal(1024);
        IntPtr sym = Marshal.AllocHGlobal(88 + 512);
        foreach (var tid in tids) {
            IntPtr th = OpenThread(0x1F03FF, false, tid);
            if (th == IntPtr.Zero) continue;
            SuspendThread(th);
            try {
                for (int i = 0; i < 1232; i++) Marshal.WriteByte(ctx, i, 0);
                Marshal.WriteInt32(ctx, 0x30, 0x10000B); // CONTEXT_FULL (AMD64)
                if (!GetThreadContext(th, ctx)) { sb.AppendLine("thread " + tid + ": GetThreadContext failed"); continue; }
                for (int i = 0; i < 1024; i++) Marshal.WriteByte(frame, i, 0);
                Marshal.WriteInt64(frame, 0, Marshal.ReadInt64(ctx, 0xF8));  Marshal.WriteInt32(frame, 12, 3); // AddrPC = Rip
                Marshal.WriteInt64(frame, 32, Marshal.ReadInt64(ctx, 0xA0)); Marshal.WriteInt32(frame, 44, 3); // AddrFrame = Rbp
                Marshal.WriteInt64(frame, 48, Marshal.ReadInt64(ctx, 0x98)); Marshal.WriteInt32(frame, 60, 3); // AddrStack = Rsp
                sb.AppendLine("== thread " + tid);
                for (int n = 0; n < maxFrames; n++) {
                    if (!StackWalk64(0x8664, proc, th, frame, ctx, IntPtr.Zero, fta, mb, IntPtr.Zero)) break;
                    ulong pc = (ulong)Marshal.ReadInt64(frame, 0);
                    if (pc == 0) break;
                    for (int i = 0; i < 88; i++) Marshal.WriteByte(sym, i, 0);
                    Marshal.WriteInt32(sym, 0, 88); Marshal.WriteInt32(sym, 80, 500);
                    ulong disp;
                    string name = SymFromAddr(proc, pc, out disp, sym) ? Marshal.PtrToStringAnsi(new IntPtr(sym.ToInt64() + 84)) + "+0x" + disp.ToString("x") : "0x" + pc.ToString("x");
                    sb.AppendLine("  " + name);
                }
            } finally { ResumeThread(th); CloseHandle(th); }
        }
        SymCleanup(proc); CloseHandle(proc);
        return sb.ToString();
    }
}
'@
$exe = (Get-Process -Id $ProcessId).Path
[StackDump]::Dump($ProcessId, (Split-Path $exe), $MaxFrames)
