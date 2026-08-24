using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Windows.Forms;

internal static class ScreenVeilLauncher
{
    [STAThread]
    private static int Main()
    {
        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(baseDirectory, "lock.ps1");

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show("Не найден lock.ps1 рядом с ScreenVeil.exe.", "ScreenVeil",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            Environment.CurrentDirectory = baseDirectory;
            using (PowerShell shell = PowerShell.Create())
            {
                shell.AddCommand(scriptPath);
                shell.Invoke();
                if (shell.HadErrors)
                {
                    string message = string.Join(Environment.NewLine,
                        shell.Streams.Error.Select(error => error.ToString()).Take(4));
                    MessageBox.Show("Не удалось запустить блокировку:\n\n" + message,
                        "ScreenVeil", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
            }
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show("Ошибка ScreenVeil:\n\n" + exception.Message, "ScreenVeil",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}


