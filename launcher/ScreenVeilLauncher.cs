using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

internal static class ScreenVeilLauncher
{
    [STAThread]
    private static int Main()
    {
        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(baseDirectory, "lock.ps1");
        string logDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScreenVeil");
        string logPath = Path.Combine(logDirectory, "launcher.log");
        bool diagnosticsOnly = Environment.GetEnvironmentVariable("SCREENVEIL_DIAGNOSTIC") == "1";

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show("Не найден lock.ps1 рядом с ScreenVeil.exe.", "ScreenVeil",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            Environment.CurrentDirectory = baseDirectory;
            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            using (PowerShell shell = PowerShell.Create())
            {
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();
                shell.Runspace = runspace;
                shell.AddCommand(scriptPath);
                if (diagnosticsOnly) shell.AddParameter("DiagnosticsOnly");
                shell.Invoke();
                if (shell.HadErrors)
                {
                    string message = string.Join(Environment.NewLine,
                        shell.Streams.Error.Select(error => error.ToString()).Take(4));
                    Directory.CreateDirectory(logDirectory);
                    File.AppendAllText(logPath, DateTime.Now.ToString("u") + " " + message + Environment.NewLine);
                    MessageBox.Show("Не удалось запустить блокировку:\n\n" + message,
                        "ScreenVeil", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
            }
            return 0;
        }
        catch (Exception exception)
        {
            Directory.CreateDirectory(logDirectory);
            File.AppendAllText(logPath, DateTime.Now.ToString("u") + " " + exception + Environment.NewLine);
            MessageBox.Show("Ошибка ScreenVeil:\n\n" + exception.Message, "ScreenVeil",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}


