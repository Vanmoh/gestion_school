part of 'chat_panel.dart';

/// Le fil d'une conversation: ses messages, sa saisie, ses actions.
///
/// Cinq cent soixante-dix lignes, soit le cœur du panneau — noyées au
/// milieu de la liste des conversations et des dialogues de groupe.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _VueDuFil on _ChatPanelState {
  Widget _buildThread(Map<String, dynamic> conversation, {required bool compact}) {
    final title = _conversationTitle(conversation);
    final online = _conversationOnline(conversation);
    final conversationId = _asInt(conversation['id']);
    final isTyping = _typingByConversation[conversationId] == true;
    final isGroup = conversation['is_group'] == true;
    final isGroupAdmin = conversation['is_group_admin'] == true;

    return Column(
      children: [
        ListTile(
          leading: compact
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => majEtat(() {
                    _storeCurrentDraft();
                    _selectedConversationId = null;
                    _messages = <Map<String, dynamic>>[];
                    _pendingInThreadCount = 0;
                  }),
                )
              : null,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            isTyping
                ? 'Ecrit...'
                // Groupe: pas de correspondant unique dont on dirait l'heure
                // de depart.
                : (isGroup
                      ? (online ? 'En ligne' : 'Hors ligne')
                      : _libellePresenceConversation(conversation)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Faire surgir la fenetre chez l'autre. Reserve au personnel:
              // la messagerie est ouverte aux eleves et aux parents, mais
              // interrompre quelqu'un ne l'est pas.
              if (_peutAppelerAttention)
                IconButton(
                  key: const Key('appeler-attention'),
                  tooltip: 'Attirer l’attention',
                  onPressed: _appelerLAttention,
                  icon: const Icon(Icons.waving_hand_outlined),
                ),
              if (!isGroup)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: online ? const Color(0xFF12B76A) : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
              if (isGroup && isGroupAdmin)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'rename') {
                      await _renameGroupConversation(conversation);
                    } else if (value == 'add') {
                      await _groupAddMember(conversation);
                    } else if (value == 'members') {
                      await _groupRemoveOrPromoteMember(conversation);
                    } else if (value == 'delete') {
                      await _deleteGroupConversation(conversation);
                    } else if (value == 'leave') {
                      await _leaveGroupConversation(conversation);
                    } else if (value == 'close') {
                      await _closeConversation(conversation);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renommer groupe')),
                    PopupMenuItem(value: 'add', child: Text('Ajouter membre')),
                    PopupMenuItem(value: 'members', child: Text('Gerer membres')),
                    PopupMenuItem(value: 'close', child: Text('Fermer groupe')),
                    PopupMenuItem(value: 'leave', child: Text('Quitter groupe')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer groupe')),
                  ],
                ),
              if (isGroup && !isGroupAdmin)
                IconButton(
                  tooltip: 'Quitter groupe',
                  onPressed: () => _leaveGroupConversation(conversation),
                  icon: const Icon(Icons.logout_outlined),
                ),
              if (!isGroup)
                IconButton(
                  tooltip: 'Fermer conversation directe',
                  onPressed: () => _closeConversation(conversation),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Chercher dans ce qui a ete dit, la ou on le lit.
        _rechercheDansLeFil(context),
        Expanded(
          child: ListView.builder(
            controller: _messageScrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (_messages.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'Aucun message pour le moment. Lance la conversation.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      if (_hasMoreMessages)
                        TextButton.icon(
                          onPressed: _loadingOlderMessages
                              ? null
                              : () => _loadMessages(conversationId, appendOlder: true),
                          icon: _loadingOlderMessages
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.history_outlined),
                          label: Text(
                            _loadingOlderMessages
                                ? 'Chargement...'
                                : 'Charger les anciens messages',
                          ),
                        )
                      else
                        Text(
                          'Debut de la conversation',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                    ],
                  ),
                );
              }

              final message = _messages[index - 1];
        final messageIndex = index - 1;
              final previousMessage = index > 1 ? _messages[index - 2] : null;
              final nextMessage = index < _messages.length ? _messages[index] : null;
              final mine = _currentUserId != null &&
                  _asInt(message['sender'] ?? message['sender_id']) == _currentUserId;
              final groupedWithPrevious =
                  _shouldGroupAttachmentMessages(message, previousMessage);
              final groupedWithNext = _shouldGroupAttachmentMessages(message, nextMessage);
              final showSender = !groupedWithPrevious;
                final attachmentRun = _attachmentRunForMessageIndex(messageIndex);
                final failedBatch = attachmentRun
                  .where(_isRetriableFailedAttachment)
                  .toList(growable: false);
                final failedBatchCount = failedBatch.length;
                final firstFailedClientMessageId = failedBatchCount > 0
                  ? _asString(failedBatch.first['client_message_id']).trim()
                  : '';
                final showBatchRetryAction = message['upload_failed'] == true &&
                  failedBatchCount > 1 &&
                  _asString(message['client_message_id']).trim() == firstFailedClientMessageId;
              final messageTime = _formatMessageTime(message['created_at']);
              final lastRead = _lastReadByConversation[conversationId] ?? 0;
              final separateur = _separateurDeJour(message, previousMessage);

              // Un appel d'attention n'est pas un propos echange: il se pose
              // au centre du fil, comme une mention de service, et non dans
              // une bulle qui le ferait lire comme un message.
              if (_asString(message['message_type']) == 'attention') {
                return Column(
                  children: [
                    ?separateur,
                    _ligneAppelAttention(context, message, messageTime),
                  ],
                );
              }

              // Un message retire garde sa place mais plus son propos.
              final retire = _asString(message['deleted_at']).trim().isNotEmpty;
              if (retire) {
                final ligne = Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block_outlined,
                            size: 14,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Message retiré',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                if (separateur == null) return ligne;
                return Column(children: [separateur, ligne]);
              }

              final bulle = Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(
                    top: groupedWithPrevious ? 2 : 5,
                    bottom: groupedWithNext ? 2 : 5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: mine
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: _messageBubbleRadius(
                      mine: mine,
                      groupedWithPrevious: groupedWithPrevious,
                      groupedWithNext: groupedWithNext,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (showSender)
                        Text(
                          _senderLabel(message),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (showSender)
                        const SizedBox(height: 2),
                      if (message['reply_to_apercu'] is Map)
                        _apercuCitation(
                          context,
                          Map<String, dynamic>.from(
                            message['reply_to_apercu'] as Map,
                          ),
                          mine: mine,
                        ),
                      if (_messageHasAttachment(message))
                        Column(
                          crossAxisAlignment:
                              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (_isImageAttachment(message))
                              Builder(
                                builder: (context) {
                                  final attachmentBytes = message['attachment_bytes'];
                                  final attachmentUrl = _asString(message['attachment_url']).trim();
                                  Widget imageChild;
                                  if (attachmentBytes is Uint8List && attachmentBytes.isNotEmpty) {
                                    imageChild = Image.memory(
                                      attachmentBytes,
                                      fit: BoxFit.cover,
                                      width: 220,
                                      height: 180,
                                    );
                                  } else if (attachmentUrl.isNotEmpty) {
                                    imageChild = Image.network(
                                      attachmentUrl,
                                      fit: BoxFit.cover,
                                      width: 220,
                                      height: 180,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 220,
                                        height: 180,
                                        color: Theme.of(context).colorScheme.surface,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.broken_image_outlined),
                                      ),
                                    );
                                  } else {
                                    imageChild = Container(
                                      width: 220,
                                      height: 180,
                                      color: Theme.of(context).colorScheme.surface,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.image_outlined),
                                    );
                                  }

                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      onTap: message['is_local_pending'] == true
                                          ? null
                                          : () => _showImageGalleryAt(messageIndex),
                                      child: imageChild,
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: message['is_local_pending'] == true
                                  ? null
                                  : () => _openAttachment(message),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _attachmentIcon(message),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _asString(message['attachment_name']).trim().isNotEmpty
                                                ? _asString(message['attachment_name']).trim()
                                                : 'Piece jointe',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatFileSize(_asInt(message['attachment_size'])),
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                          if (_isPdfAttachment(message) &&
                                              message['is_local_pending'] != true)
                                            Text(
                                              'Aperçu PDF disponible',
                                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(context).colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          if (message['is_local_pending'] == true)
                                            Text(
                                              'Upload: ${_asInt(message['upload_progress'])}%',
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          if (message['upload_failed'] == true)
                                            Text(
                                              (_asString(message['upload_error']).trim().isNotEmpty)
                                                  ? _asString(message['upload_error']).trim()
                                                  : 'Echec de l\'upload',
                                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(context).colorScheme.error,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (message['is_local_pending'] != true) ...[
                                      const SizedBox(width: 8),
                                      if (message['upload_failed'] == true)
                                        IconButton(
                                          tooltip: 'Reessayer',
                                          onPressed: _sending ? null : () => _retryFailedFileUpload(message),
                                          icon: const Icon(Icons.refresh_rounded),
                                        )
                                      else
                                        const Icon(Icons.download_outlined),
                                    ] else ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Annuler l\'upload',
                                        onPressed: _asString(message['client_message_id']) == _activeUploadClientMessageId
                                            ? _cancelActiveUpload
                                            : null,
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (showBatchRetryAction)
                              Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TextButton.icon(
                                    onPressed: _sending
                                        ? null
                                        : () => _retryFailedAttachmentBatchFrom(messageIndex),
                                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                                    label: Text('Reessayer le lot ($failedBatchCount)'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (_messageHasAttachment(message) && _asString(message['content']).trim().isNotEmpty)
                        const SizedBox(height: 6),
                      if (_asString(message['content']).trim().isNotEmpty)
                        _texteAvecMentions(
                          context,
                          _asString(message['content']),
                        ),
                      if (messageTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            // « modifié » accole a l'heure: sans lui, un
                            // message corrige apres coup se lirait comme
                            // celui d'origine.
                            _asString(message['edited_at']).trim().isEmpty
                                ? messageTime
                                : '$messageTime · modifié',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      if (mine)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _outgoingStatusLabel(message, lastRead),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
              );

              // Corriger et retirer se trouvent sous un appui long, sur ses
              // propres messages seulement: le serveur refuse les autres, et
              // proposer un geste qui mene a un refus ne vaut rien.
              final interactive = GestureDetector(
                key: Key('message-actions-${_asInt(message['id'])}'),
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _ouvrirLesActionsDuMessage(message, mine),
                onSecondaryTap: () => _ouvrirLesActionsDuMessage(message, mine),
                child: bulle,
              );

              if (separateur == null) return interactive;
              return Column(children: [separateur, interactive]);
            },
          ),
        ),
        const Divider(height: 1),
        if (_pendingInThreadCount > 0)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () {
                  majEtat(() => _pendingInThreadCount = 0);
                  _scrollToBottom();
                  if (conversationId > 0) {
                    unawaited(_markRead(conversationId));
                  }
                },
                icon: const Icon(Icons.arrow_downward),
                label: Text('$_pendingInThreadCount nouveaux messages'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sendError != null) ...[
                Text(
                  _sendError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ?_suggestionsDeMention(context),
              if (_messageCite != null) _bandeauCitation(context),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Envoyer un fichier',
                    onPressed: _sending ? null : _sendFile,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  if (_activeUploadCancelToken != null) ...[
                    IconButton(
                      tooltip: 'Annuler l\'upload en cours',
                      onPressed: _cancelActiveUpload,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: _onInputChanged,
                      onTap: () {
                        if (_pendingInThreadCount > 0) {
                          majEtat(() => _pendingInThreadCount = 0);
                        }
                      },
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Ecrire un message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
