<script lang="ts">
  import RecipeForm from '$lib/components/RecipeForm.svelte';

  let { data, form } = $props();
  const recipe = data.recipe;
</script>

<svelte:head>
  <title>Edit {recipe.title} — The Sharp Edge</title>
</svelte:head>

<RecipeForm
  mode="edit"
  {recipe}
  {form}
  eyebrow="Edit recipe"
  heading={recipe.title}
  submitLabel="Save new version"
  cancelHref="/r/{recipe.slug}"
/>
