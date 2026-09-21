```
   █████╗ ███████╗███████╗███╗   ██╗████████╗██╗   ██╗███╗   ███╗
  ██╔══██╗██╔════╝██╔════╝████╗  ██║╚══██╔══╝██║   ██║████╗ ████║
  ███████║███████╗█████╗  ██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║
  ██╔══██║╚════██║██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██║╚██╔╝██║
  ██║  ██║███████║███████╗██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║
  ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝
         V A L I D A T O R   ·   I N C E N T I V I Z E D   T E S T N E T
```

# Asentum Validator Guide — Season 1

A tested, step-by-step guide to running an **Asentum testnet validator** on a cheap VPS, with fixes for the problems the official installer hits today (stuck sync, rejected bond, DNS errors).

> Written from a real install on 21 Sep 2026. My validator has been signing since block 69,721.

---

## Why Asentum

- **Post-quantum L1.** Validator keys are Dilithium3, not the ECDSA keys every other EVM chain uses.
- **Consumer hardware.** Built for a normal PC: the official floor is a Raspberry Pi 4.
- **Incentivized testnet is live** since 17 Sep 2026. **15% of the $ASE supply** is reserved for validator rewards, plus **6%** for the testnet campaign.
- **Validator XP is based on blocks signed, not stake.** Being early and staying online beats having a big bag.
- Bonding a validator gives a **+5,000 XP milestone** and a **permanent ×1.2 multiplier** on everything you earn afterwards.

> ⚠️ The XP → $ASE conversion rate is **not published yet**. Treat this as a free-to-cheap bet, not guaranteed income.

---

## How it works

```
  ┌──────────────┐   install    ┌──────────────┐   sync    ┌──────────────┐
  │   VPS        │ ───────────▶ │  Asentum     │ ────────▶ │  caught up   │
  │ Ubuntu 24.04 │              │  node        │           │  with chain  │
  └──────────────┘              └──────────────┘           └──────┬───────┘
                                                                  │ faucet: 500+ test ASE
                                                                  ▼
  ┌──────────────┐    pair      ┌──────────────┐   bond    ┌──────────────┐
  │  airdrop     │ ◀─────────── │  Telegram    │ ◀──────── │  validator   │
  │  portal (XP) │              │  @AsentumBot │  import   │  signing ✔   │
  └──────────────┘              └──────────────┘   key     └──────────────┘
```

---

## 1. Get a server

| Spec | Minimum | What I use |
|---|---|---|
| CPU | 2 vCPU | 6 vCPU |
| RAM | 4 GB | 12 GB |
| Disk | 40 GB SSD | 200 GB SSD |
| OS | Ubuntu 22.04 / 24.04 or Debian | Ubuntu 24.04 |
| Uptime | 24/7 | 24/7 |

Any VPS provider works. Cheap options: Contabo (≈ €5–9/mo), Hetzner CX23 (≈ €5.5/mo). **Avoid 1 GB RAM plans**: they're below the official floor.

Keep it **24/7**. Validator XP comes from signed blocks, and the streak multiplier resets if you go offline.

## 2. Install the node

SSH in as `root` and run the **official** installer:

```bash
curl -fsSL https://testnet.asentum.com/install/validator | bash
```

It installs Node.js 22, downloads the chain snapshot, sets up the firewall and a `systemd` service, then waits for sync.

<details>
<summary><b>"Could not resolve host" / Node.js 18 got installed?</b> Fix DNS first.</summary>

Some fresh VPS images have flaky DNS in their first minutes. The installer then fails to download the bundle, and NodeSource fails too, so you end up with Ubuntu's Node 18. Fix:

```bash
mkdir -p /etc/systemd/resolved.conf.d
printf "[Resolve]\nDNS=1.1.1.1 8.8.8.8\nFallbackDNS=1.0.0.1 8.8.4.4\n" > /etc/systemd/resolved.conf.d/dns.conf
systemctl restart systemd-resolved
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs
node -v   # must be v22.x
```
Then run the installer again.
</details>

## 3. Sync (and the 99% trap)

You'll see a progress bar like this:

```
‣ Syncing blockchain …
  [█████████████████████████████████████████░]  99%  69639 / 69659 blocks
```

**Tip 1: use a fresh snapshot.** The team re-publishes the snapshot **every hour (~:08 UTC)**. An old snapshot can leave you 500+ blocks behind, and catching up at that rate takes **hours**. Check the snapshot's age:

```bash
curl -sI https://testnet.asentum.com/install/chain-snapshot-light.tar.gz | grep -i last-modified
```

If it's more than ~20 min old, wait for the next one, then re-run the installer. Your `validator.key` is preserved.

**Tip 2: stuck at 99% forever?** In pull mode the node stays **~20 blocks behind** the finalized head, so the installer's "fully synced" check never passes. This is expected, and the node joins live consensus once bonded. If the gap stays around 20 and doesn't grow, press **Ctrl+C** and finish with the fix script in step 4.

## 4. Bond the validator

If the installer finished and printed `VALIDATOR LIVE`, skip to step 5.

If it stopped at the 99% sync, **or** the bond failed with:

```
Error: transaction rejected: insufficient balance for value plus gas
```

run my fix script. It reuses the official installer's own post-sync steps (address, key backup, faucet, bond) and raises the gas buffer from 1 to 10 ASE, because 1 ASE isn't enough to pay for the bond tx:

```bash
curl -fsSL https://raw.githubusercontent.com/getcakedieyoungx/asentum-validator-guide/main/scripts/finish-bond.sh | bash
```

> Only run it **once**, on a validator that is **not bonded yet**. Check first with `asentum-validator status`: if it says `bonded stake 0 ASE`, you're good to run it.

## 5. Back up your key (do it now)

```bash
cat /opt/asentum/data/validator.key.hex
```

Those 64 hex characters **are** your validator. If you lose them, you lose the validator: there is no recovery. Put them in a password manager. **Never paste them into a chat or a group.**

## 6. Link the validator to the airdrop portal

1. Open the portal: **https://airdrop.asentum.com/?r=ZSKCEPK7** *(my referral link)*
2. Start **@AsentumBot** in Telegram. Open it from the portal's *Pair Telegram wallet* button so you know it's the real bot.
3. Tap **Import existing wallet** (not *Create wallet*) and paste your 64-char key.
4. Check that the bot shows **your validator address** (`ase1…`, the same one `asentum-validator status` prints).
5. Delete the message with your key from the Telegram chat.
6. In the portal, open **Pair Telegram wallet**, then in the bot tap **Connect wallet** and enter the 6-digit code.
7. When the bot asks *"Auto-approve transactions?"*, answer **No**.

> ❌ **Don't import the key into MetaMask.** It's a post-quantum (Dilithium3) key. MetaMask will derive an unrelated `0x…` address and your XP won't be linked.

## 7. Check that you're signing

```bash
curl -fsSL https://raw.githubusercontent.com/getcakedieyoungx/asentum-validator-guide/main/scripts/check.sh | bash
```

Healthy output:

```
  ASENTUM VALIDATOR · HEALTH CHECK
  address          ase129n6u00uatdeumumehx66x26j58thd2npnkvw9
  service          active
  network status   active
  committee        signing
  last voted       70481   (network finalized 70476)
  misses in a row  1
  wallet           15.005321 ASE
  ✔ looks healthy
```

A new bond shows as `pending` first, then `active / signing` after the next epoch (300 blocks, ~20–25 min). A few misses that keep resetting back to 0–1 are normal.

---

## Useful commands

```bash
asentum-validator status      # address, stake, height, status
asentum-validator earnings    # wallet balance (block rewards land here)
asentum-validator logs        # live logs
asentum-validator restart     # restart the service
asentum-validator update      # after a chain upgrade (keeps key + bond)
```

## Ports

| Port | Why | Open to |
|---|---|---|
| 22 | SSH | you |
| 8545 | RPC / `broadcastUrl`: other validators deliver blocks & votes here | public (**keep it open**) |
| 9000 | ANT consensus transport | the 4 bootstrap peers only (installer sets this) |

## Free XP boosts

- **Streak:** one transaction per UTC day. ×1.1 at day 3, ×1.5 at day 7, ×2 at day 30, ×3 at day 100. The portal's *Get 5 test ASE* button gives you gas every 6 h.
- **Link X:** ×1.1
- **Referrals:** you earn 5% of your referrals' XP, forever.

## FAQ

**Does bonding more ASE give more XP?** No. Validator XP is based on blocks signed. The 500 ASE minimum is enough, and it comes free from the faucet.

**Peers shows 0. Is that bad?** No. Installed validators run in pull mode and talk to the bootstrap relays. What matters is `committee: signing`.

**Can I run it on my home PC?** Yes (there's also a desktop "Asentum Operator" app), but it must stay online 24/7 to keep signing.

---

## Links

- Airdrop portal: https://airdrop.asentum.com/?r=ZSKCEPK7 *(referral)*
- Validators explorer: https://explorer.asentum.com/validators
- Network: https://www.asentum.com/network
- Telegram wallet: [@AsentumBot](https://t.me/AsentumBot)
- Telegram Group: https://t.me/getcakedieyoungx

## Disclaimer

Community guide, not affiliated with Asentum. Testnet tokens have no guaranteed value, and reward terms can change. Scripts are provided as-is. Read them before running anything as root.

MIT License
