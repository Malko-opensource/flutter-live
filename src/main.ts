import {mount} from 'svelte';
import '@imfacto/svelte/styles.css';
import '@imfacto/svelte/fonts.css';
import './style.css';
import App from './App.svelte';
mount(App,{target:document.getElementById('app')!});
