# Sudo runbook — PX13 investigation

Commands that require root. Run after pull/reboot as needed.

## Install hardened userspace fix

```bash
sudo ~/snd_repair/scripts/install-px13-audio-fix.sh
sudo ~/snd_repair/scripts/install-fw-validation-service.sh --suspend-only
sudo systemctl daemon-reload
```

## Track C — webcam groups (logout required after)

```bash
sudo usermod -aG video,render "$USER"
# log out and back in, or: sudo reboot
```

## Track A — production kernel modules (optional)

```bash
cd ~/snd_repair
./scripts/build-from-upstream.sh
sudo ./scripts/install-tas2783-ko.sh
sudo reboot
```

## Recovery

```bash
sudo reboot                                    # FW :8 stuck after bad resume
sudo /usr/local/sbin/px13-audio-fix.sh         # manual PCI reset (may still need reboot)
~/snd_repair/scripts/px13-restore-pipewire.sh  # no sudo — restore PipeWire only
```

## Validation linger (optional)

```bash
sudo loginctl enable-linger "$USER"
```

## Rollback px13 script

```bash
sudo ~/snd_repair/scripts/install-px13-audio-fix.sh --remove
```
