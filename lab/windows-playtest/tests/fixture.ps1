# Synthetic Windows GUI target: public CI never needs original game assets.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = 'OpenLRR Fixture - Main Menu'
$form.ClientSize = New-Object System.Drawing.Size(320, 190)
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(100, 100)
$form.BackColor = [System.Drawing.Color]::DarkSlateGray
$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point(40, 40)
$button.Size = New-Object System.Drawing.Size(160, 55)
$button.Text = 'Start'
$button.Add_Click({
  $form.Text = 'OpenLRR Fixture - In Game'
  $form.BackColor = [System.Drawing.Color]::DarkGoldenrod
  $button.Text = 'Started'
})
$form.Controls.Add($button)
[System.Windows.Forms.Application]::Run($form)
