import http from "k6/http";
import { BASE_URL } from "../config/base-options.ts";

const BASE_LAT = -16.4757;
const BASE_LON = -54.6685;

const OBSERVATIONS = [
  "Descarte irregular de resíduos sólidos na via pública",
  "Acúmulo de lixo em terreno baldio",
  "Entulho depositado sobre calçada sem autorização",
  "Resíduos eletrônicos abandonados em área residencial",
  "Lixo doméstico descartado fora do horário de coleta",
  "Resíduos de construção civil lançados em área pública",
  "Descarte de móveis e eletrodomésticos em logradouro",
];

export function fetchCategoryIds(): string[] {
  const res = http.get(`${BASE_URL}/v1/waste-categories`);
  if (res.status !== 200) return [];
  return (res.json("categories") as Array<{ id: string }>).map((c) => c.id);
}

export function randomCategoryId(ids: string[]): string | null {
  if (ids.length === 0) return null;
  return ids[Math.floor(Math.random() * ids.length)];
}

export function makeComplaintBody(categoryId: string): string {
  const lat = BASE_LAT + (Math.random() - 0.5) * 0.1;
  const lon = BASE_LON + (Math.random() - 0.5) * 0.1;
  const obs = OBSERVATIONS[Math.floor(Math.random() * OBSERVATIONS.length)];

  return JSON.stringify({
    date: new Date().toISOString(),
    observations: obs,
    geospatial: {
      heading: null,
      location: {
        coords: {
          latitude: lat,
          longitude: lon,
          altitude: null,
          accuracy: null,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: Date.now(),
      },
      addresses: {
        city: "Cuiabá",
        district: null,
        streetNumber: null,
        street: null,
        region: "MT",
        subregion: null,
        country: "Brasil",
        postalCode: null,
        name: null,
        isoCountryCode: "BR",
        timezone: "America/Cuiaba",
        formattedAddress: null,
      },
    },
    waste_category_ids: [categoryId],
  });
}
