import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// The shop's connector link for ChatGPT / Claude: the shop-mcp edge
/// function on this app's own Supabase project (migration 0086).
String get aiConnectorUrl =>
    '${dotenv.env['SUPABASE_URL'] ?? ''}/functions/v1/shop-mcp';

/// Connect ChatGPT / Claude: the link to copy and how to add it. Who may
/// use it mirrors ai_context(): the plan must include the AI assistant,
/// staff need the owner's permission.
class AiAssistantScreen extends ConsumerWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(appContextProvider).value;
    final inPlan = ctx?.aiInPlan ?? false;
    final allowed = inPlan && (ctx?.canUseAi ?? false);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('ChatGPT & Claude')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconChip(
                    Icons.auto_awesome,
                    color: AppColors.primary,
                    size: 44,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Run your shop by chatting with AI'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t(
                            'Connect Dukania to ChatGPT or Claude and ask in plain words: who owes you money, what is running low, how much you sold this week.',
                          ),
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!inPlan)
            _NotYet(
              title: t('Not in your plan yet'),
              body: ctx?.isOwner ?? false
                  ? t(
                      'The AI assistant is an add-on. Ask Dukania to add it to your plan.',
                    )
                  : t(
                      'The AI assistant isn\'t in your shop\'s plan. Ask the shop owner.',
                    ),
              action: ctx?.isOwner ?? false
                  ? FilledButton.icon(
                      icon: const Icon(Icons.chat),
                      label: Text(t('Ask Dukania on WhatsApp')),
                      onPressed: () => launchWhatsAppContact(
                        context,
                        ctx,
                        customReason:
                            'I want the AI assistant (ChatGPT / Claude) for my shop.',
                      ),
                    )
                  : null,
            )
          else if (!allowed)
            _NotYet(
              title: t('Ask the shop owner'),
              body: t(
                'The shop owner hasn\'t allowed you to use the AI assistant. They can turn it on for you in Staff & Permissions.',
              ),
            )
          else ...[
            SectionLabel(t('Your connection link')),
            const _LinkCard(),
            SectionLabel(t('Add it to ChatGPT')),
            _Steps([
              t('In ChatGPT (chatgpt.com), open Plugins and press Add.'),
              t(
                'Paste the link as the Server URL, choose OAuth, tick "I understand", then press Create.',
              ),
              t(
                'Sign in with your Dukania email and password, then press Allow.',
              ),
            ]),
            SectionLabel(t('Add it to Claude')),
            _Steps([
              t(
                'In Claude (claude.ai), open Settings → Connectors and press Add custom connector.',
              ),
              t('Name it Dukania, paste the link, then press Add.'),
              t(
                'Press Connect, sign in with your Dukania email and password, then press Allow.',
              ),
            ]),
            SectionLabel(t('Try asking')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in [
                      t('How is my shop doing today?'),
                      t('Who owes me money?'),
                      t('What is running low?'),
                      t('Show this week\'s sales.'),
                      t('Bill 2 Parle-G to Ramesh, paid by UPI.'),
                    ])
                      Chip(label: Text(q)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                'It sees only what you can see in Dukania. It can also make bills, take payments and add products, but it always shows you a preview first and saves only after you say yes. Some ChatGPT and Claude plans don\'t allow connectors.',
              ),
              style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
            ),
            if (ctx?.isOwner ?? false) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: Text(t('Let staff use it too: Staff & Permissions')),
                onPressed: () => context.push('/staff'),
              ),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                aiConnectorUrl,
                key: const Key('ai-connector-url'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('ai-copy-link'),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(t('Copy link')),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: aiConnectorUrl));
                if (context.mounted) showSuccess(context, t('Link copied'));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotYet extends StatelessWidget {
  const _NotYet({required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: AppColors.inkSoft, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
