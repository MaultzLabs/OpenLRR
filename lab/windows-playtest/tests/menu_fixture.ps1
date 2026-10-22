# Windows native HMENU fixture for Cheats > No NERPs.
# No game files, injected commands, or desktop capture required.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;

public class OpenLRRMenuFixture : Form
{
    const uint MF_POPUP = 0x0010;
    const uint MF_STRING = 0x0000;
    const uint MF_BYCOMMAND = 0x0000;
    const uint MF_CHECKED = 0x0008;
    const uint MF_UNCHECKED = 0x0000;
    const uint NO_NERPS_ID = 401;

    [DllImport("user32.dll")] static extern IntPtr CreateMenu();
    [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool AppendMenuW(IntPtr hMenu, uint flags, UIntPtr id, string text);
    [DllImport("user32.dll")] static extern bool SetMenu(IntPtr hwnd, IntPtr menu);
    [DllImport("user32.dll")] static extern bool DrawMenuBar(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint CheckMenuItem(IntPtr menu, uint id, uint flags);

    private IntPtr rootMenu;
    private IntPtr cheatsMenu;
    private bool noNerps;
    public OpenLRRMenuFixture()
    {
        Text = "OpenLRR Menu Fixture";
        ClientSize = new Size(420, 230);
        StartPosition = FormStartPosition.Manual;
        Location = new Point(90, 90);
        BackColor = Color.DarkSlateGray;
    }
    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        rootMenu = CreateMenu();
        cheatsMenu = CreatePopupMenu();
        if (rootMenu == IntPtr.Zero || cheatsMenu == IntPtr.Zero)
            throw new InvalidOperationException("Cannot create native menus");
        AppendMenuW(rootMenu, MF_POPUP,
            new UIntPtr(unchecked((ulong)cheatsMenu.ToInt64())), "&Cheats");
        AppendMenuW(cheatsMenu, MF_STRING, new UIntPtr(NO_NERPS_ID), "No &NERPs");
        if (!SetMenu(this.Handle, rootMenu))
            throw new InvalidOperationException("SetMenu failed");
        DrawMenuBar(this.Handle);
    }
    protected override void WndProc(ref Message msg)
    {
        if (msg.Msg == 0x0111 && (msg.WParam.ToInt64() & 0xFFFF) == NO_NERPS_ID)
        {
            noNerps = !noNerps;
            CheckMenuItem(cheatsMenu, NO_NERPS_ID,
                MF_BYCOMMAND | (noNerps ? MF_CHECKED : MF_UNCHECKED));
            this.Text = noNerps ? "OpenLRR Menu Fixture - No NERPs" : "OpenLRR Menu Fixture";
        }
        base.WndProc(ref msg);
    }
}
'@ -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')
$form = New-Object OpenLRRMenuFixture
[System.Windows.Forms.Application]::Run($form)
