/**
 * N8N Webhook Processor pour Baserow → Mes-Démarches
 *
 * Ce script analyse les webhooks Baserow pour détecter les changements
 * et préparer les données pour la synchronisation avec Mes-Démarches.
 *
 * Fonctionnalités :
 * - Détection des champs modifiés en comparant items vs old_items
 * - Aplatissement des valeurs complexes (dropdown, utilisateurs, liens)
 * - Extraction séparée des métadonnées de modification
 * - Calcul des délais entre modifications pour détecter les conflits
 *
 * Usage dans N8N :
 * 1. Créer un Function Node
 * 2. Coller ce code dans le node
 * 3. Les données traitées seront disponibles dans $json.processedRows
 */

// Code n8n - Function node amélioré
const items = $json;

function flattenValue(value) {
  // Si c'est un objet avec un attribut 'value' (dropdown)
  if (value && typeof value === 'object' && value.value) {
    return value.value;
  }

  // Si c'est un array d'objets avec 'value' (multiple select)
  if (Array.isArray(value)) {
    return value.map(item => {
      if (item && typeof item === 'object' && item.value) {
        return item.value;
      }
      return item;
    }).join(', ');
  }

  // Si c'est un objet avec 'name' (utilisateur)
  if (value && typeof value === 'object' && value.name) {
    return value.name;
  }

  // Si c'est un objet avec 'url' et 'label' (lien)
  if (value && typeof value === 'object' && value.url && value.label) {
    return value.url;
  }

  return value;
}

function extractMetadata(row) {
  const metadata = {
    lastModified: null,
    lastModifiedBy: null,
    lastModifiedByName: null
  };

  // Extraction de la date de dernière modification
  const lastModField = row["Dernière modification"];
  if (lastModField) {
    Object.assign(metadata, { lastModified: lastModField });
  }

  // Extraction de l'utilisateur qui a modifié
  const lastModByField = row["Dernière modification par"];
  if (lastModByField && typeof lastModByField === 'object') {
    Object.assign(metadata, {
      lastModifiedBy: lastModByField.id,
      lastModifiedByName: lastModByField.name
    });
  }

  return metadata;
}

function analyzeChanges(currentRow, previousRow) {
  const changedItems = {};

  // Obtenir toutes les clés des deux objets
  const allKeys = new Set([
    ...Object.keys(currentRow || {}),
    ...Object.keys(previousRow || {})
  ]);

  allKeys.forEach(key => {
    // Exclure les champs de métadonnées de l'analyse des changements
    // car ils sont traités séparément
    if (key === "Dernière modification" || key === "Dernière modification par") {
      return;
    }

    const currentValue = flattenValue(currentRow[key]);
    const previousValue = flattenValue(previousRow[key]);

    // Normaliser les valeurs pour comparaison
    const normalizeCurrent = currentValue === null || currentValue === undefined ? '' : String(currentValue);
    const normalizePrevious = previousValue === null || previousValue === undefined ? '' : String(previousValue);

    if (normalizeCurrent !== normalizePrevious) {
      changedItems[key] = {
        before: previousValue,
        after: currentValue,
        beforeFlattened: normalizePrevious,
        afterFlattened: normalizeCurrent
      };
    }
  });

  return changedItems;
}

// Traiter chaque item du webhook
const processedItems = items.map(item => {
  const webhookBody = item.body;

  // Traiter chaque ligne modifiée
  const processedRows = webhookBody.items.map((currentRow, index) => {
    const previousRow = webhookBody.old_items[index];

    // Extraire les métadonnées séparément
    const currentMetadata = extractMetadata(currentRow);
    const previousMetadata = extractMetadata(previousRow);

    // Analyser les changements (sans les métadonnées)
    const changedItems = analyzeChanges(currentRow, previousRow);

    // Aplatir les valeurs dans la ligne courante (sans les métadonnées)
    const flattenedCurrentRow = {};
    Object.keys(currentRow).forEach(key => {
      if (key !== "Dernière modification" && key !== "Dernière modification par") {
        flattenedCurrentRow[key] = flattenValue(currentRow[key]);
      }
    });

    // Calculer le délai entre les modifications
    let timeBetweenChanges = null;
    if (currentMetadata.lastModified && previousMetadata.lastModified) {
      const currentTime = new Date(currentMetadata.lastModified);
      const previousTime = new Date(previousMetadata.lastModified);
      timeBetweenChanges = currentTime.getTime() - previousTime.getTime(); // en milliseconds
    }

    return {
      // Données originales
      id: currentRow.id,
      originalRow: currentRow,
      previousRow: previousRow,

      // Données aplaties (sans métadonnées)
      flattenedRow: flattenedCurrentRow,

      // Changements détectés (sans métadonnées)
      changedItems: changedItems,
      changedFields: Object.keys(changedItems),
      changeCount: Object.keys(changedItems).length,

      // Métadonnées extraites séparément
      metadata: {
        current: currentMetadata,
        previous: previousMetadata,
        timeBetweenChanges: timeBetweenChanges,
        timeBetweenChangesHuman: timeBetweenChanges ? `${Math.round(timeBetweenChanges / 1000)}s` : null
      },

      // Informations pour la synchronisation MD
      syncInfo: {
        baserowUserId: currentMetadata.lastModifiedBy,
        baserowUserName: currentMetadata.lastModifiedByName,
        lastModifiedAt: currentMetadata.lastModified,
        previousModifiedAt: previousMetadata.lastModified,
        shouldCheckMDConflicts: timeBetweenChanges !== null && timeBetweenChanges < 300000 // 5 minutes
      },

      // Utilitaires
      hasChanges: Object.keys(changedItems).length > 0,
      dossierNumber: currentRow.dossier || currentRow.Projet
    };
  });

  return {
    // Métadonnées du webhook
    webhook_id: webhookBody.webhook_id,
    event_id: webhookBody.event_id,
    event_type: webhookBody.event_type,
    table_id: webhookBody.table_id,
    webhook_timestamp: new Date().toISOString(),

    // Données traitées
    processedRows: processedRows,
    totalRows: processedRows.length,
    rowsWithChanges: processedRows.filter(row => row.hasChanges).length,

    // Données originales (pour debug)
    originalData: item
  };
});

return processedItems;

/**
 * Exemple de structure de sortie :
 *
 * {
 *   "webhook_id": 1,
 *   "event_type": "rows.updated",
 *   "processedRows": [
 *     {
 *       "id": 11,
 *       "changedItems": {
 *         "dossier": {
 *           "before": undefined,
 *           "after": 554103,
 *           "beforeFlattened": "",
 *           "afterFlattened": "554103"
 *         }
 *       },
 *       "metadata": {
 *         "current": {
 *           "lastModified": "2025-09-26T17:40:15.958603Z",
 *           "lastModifiedBy": 1,
 *           "lastModifiedByName": "Hono Uira"
 *         },
 *         "timeBetweenChanges": 39073
 *       },
 *       "syncInfo": {
 *         "baserowUserId": 1,
 *         "baserowUserName": "Hono Uira",
 *         "shouldCheckMDConflicts": true
 *       },
 *       "flattenedRow": {
 *         "Type de projet": "Fonctionnement",  // ← Valeur aplatie
 *         "Type de commission": "CTJEP"        // ← Valeur aplatie
 *       },
 *       "dossierNumber": 554103
 *     }
 *   ]
 * }
 *
 * Utilisation dans les nodes suivants :
 * - $json.processedRows[0].changedItems → Champs modifiés
 * - $json.processedRows[0].syncInfo.baserowUserName → Utilisateur
 * - $json.processedRows[0].dossierNumber → N° dossier pour MD
 * - $json.processedRows[0].syncInfo.shouldCheckMDConflicts → Vérifier conflits
 */