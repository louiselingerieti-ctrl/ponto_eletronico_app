import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/layout/cdf_layout.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import 'request_detail_page.dart';
import 'request_models.dart';

class NewRequestPage extends StatefulWidget {
  const NewRequestPage({super.key});

  @override
  State<NewRequestPage> createState() => _NewRequestPageState();
}

class _NewRequestPageState extends State<NewRequestPage> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  RequestCategory _category = RequestCategory.detectionProblem;
  DateTime? _date;
  TimeOfDay? _time;
  bool _submitting = false;
  bool _touched = false;

  bool get _dirty =>
      _touched || _description.text.trim().isNotEmpty || _time != null;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = AppScope.backendOf(context).now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DatesPt.dateOnly(now),
      firstDate: DateTime(now.year - 1),
      lastDate: DatesPt.dateOnly(now),
      helpText: 'Data do ocorrido',
    );
    if (d != null) {
      setState(() {
        _date = d;
        _touched = true;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Horário (opcional)',
    );
    if (t != null) {
      setState(() {
        _time = t;
        _touched = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return; // evita envio duplicado
    if (!(_form.currentState?.validate() ?? false)) return;
    final b = AppScope.backendOf(context);
    setState(() => _submitting = true);
    try {
      final r = await b.submit(
        RequestDraft(
          category: _category,
          date: _date ?? DatesPt.dateOnly(b.now()),
          time: _time,
          description: _description.text,
        ),
        online: !b.offline,
      );
      if (!mounted) return;
      _touched = false;
      _description.clear();
      await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => RequestDetailPage(displayId: r.displayId)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _leave() async {
    final nav = Navigator.of(context);
    if (!_dirty) {
      nav.pop();
      return;
    }
    final discard = await confirmDialog(
      context,
      title: 'Descartar solicitação?',
      message: 'O que você escreveu ainda não foi salvo nem enviado.',
      confirm: 'Descartar',
      cancel: 'Continuar editando',
    );
    if (discard && mounted) {
      _touched = false;
      _description.clear();
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = AppScope.backendOf(context);
    final c = context.cdf;
    final date = _date ?? DatesPt.dateOnly(b.now());
    final offline = b.offline;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: Form(
          key: _form,
          autovalidateMode: _touched ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: PageBody(children: [
            const PageIntro('Nova solicitação', 'Conte o que aconteceu.'),
            const FieldLabel('Qual foi o problema?'),
            DropdownButtonFormField<RequestCategory>(
              initialValue: _category,
              isExpanded: true,
              icon: Icon(Lucide.chevronDown, size: CdfSize.icon, color: c.ink),
              style: cdfText(16, color: c.ink),
              dropdownColor: c.paper,
              decoration: cdfInput(context),
              items: [
                for (final cat in RequestCategory.values)
                  DropdownMenuItem(value: cat, child: Text(cat.label)),
              ],
              onChanged: (v) => setState(() {
                _category = v ?? _category;
                _touched = true;
              }),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _PickerField(
                  label: 'Data do ocorrido',
                  value: DatesPt.numeric(date),
                  icon: Lucide.calendar,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerField(
                  label: 'Horário (opcional)',
                  value: _time == null ? '--:--' : _time!.format(context),
                  placeholder: _time == null,
                  icon: Lucide.clock,
                  onTap: _pickTime,
                ),
              ),
            ]),
            const FieldLabel('Descreva o ocorrido'),
            TextFormField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              maxLength: RequestDraft.maxDescription,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  currentLength > RequestDraft.maxDescription - 200
                      ? Text('$currentLength/$maxLength', style: cdfText(12, color: c.sub))
                      : null,
              style: cdfText(16, color: c.ink, height: 1.4),
              decoration: cdfInput(context,
                  hint: 'Explique o problema e o que precisa ser revisado.'),
              validator: RequestDraft.validateDescription,
              onChanged: (_) {
                if (!_touched) setState(() => _touched = true);
              },
            ),
            Note(offline
                ? 'Sem internet. Nesta demonstração, você poderá guardar um rascunho até a conexão voltar.'
                : 'A solicitação será encaminhada para análise da empresa nesta demonstração.'),
            PrimaryButton(
              _submitting
                  ? 'Enviando…'
                  : offline
                      ? 'Guardar rascunho de demonstração'
                      : 'Enviar solicitação de demonstração',
              top: 0,
              onPressed: _submitting ? null : _submit,
            ),
            TextAction('Cancelar', onPressed: _leave),
          ]),
        ),
      ),
    );
  }
}

/// Campo que abre o seletor nativo de data/hora.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.placeholder = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FieldLabel(label),
      Semantics(
        button: true,
        label: '$label: ${placeholder ? 'não informado' : value}',
        excludeSemantics: true,
        child: Material(
          color: c.paper,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.line),
            borderRadius: BorderRadius.circular(CdfSize.radiusField),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(CdfSize.radiusField),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(CdfLayout.of(context).fieldPadding),
              child: Row(children: [
                Expanded(
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: cdfText(16, color: placeholder ? c.sub : c.ink)),
                ),
                Icon(icon, size: CdfSize.icon, color: c.ink),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
