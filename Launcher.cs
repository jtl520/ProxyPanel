using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;
class Launcher {
    [STAThread]
    static void Main() {
        try {
            using (var runspace = RunspaceFactory.CreateRunspace())
            using (var ps = PowerShell.Create()) {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();
                ps.Runspace = runspace;
                ps.AddScript("Set-ExecutionPolicy -Scope Process Bypass -Force").Invoke();
                ps.Commands.Clear();
                ps.AddCommand(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ProxyPanel.ps1"));
                ps.Invoke();
                if (ps.HadErrors) MessageBox.Show("Unable to open panel. " + ps.Streams.Error[0].ToString(), "Proxy Panel");
            }
        } catch (Exception e) { MessageBox.Show(e.Message, "Proxy Panel"); }
    }
}
