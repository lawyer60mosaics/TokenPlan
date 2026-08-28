<script setup>
// Keep the in-app notice and distributed license document in sync, offline.
import notices from '../THIRD_PARTY_NOTICES.md?raw';

// This document only uses headings and emphasis. Render as Vue text nodes,
// never as raw HTML; no remote document fetch or navigation is required.
const blocks = notices.trim().split(/\r?\n\s*\r?\n/).map(text => {
  const heading = text.match(/^(#{1,2}) /);
  return {
    tag: heading ? (heading[1].length === 1 ? 'h2' : 'h3') : 'p',
    parts: (heading ? text.slice(heading[0].length) : text).split('**'),
  };
});
</script>

<template>
  <article class="notices-content">
    <component :is="block.tag" v-for="(block, index) in blocks" :key="index">
      <template v-for="(part, partIndex) in block.parts" :key="partIndex"><strong v-if="partIndex % 2">{{ part }}</strong><template v-else>{{ part }}</template></template>
    </component>
  </article>
</template>
