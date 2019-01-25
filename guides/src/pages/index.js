// --- Dependencies
import * as React from 'react'

// --- Components
import Layout from 'components/Layout'
import Section from 'components/Section'

// --- Images
import LogoSpark from 'components/LogoSpark'

/**
 * Component
 */

const IndexPage = () => (
  <Layout pathname="/" title="Home">
    <div className="center mw9 ph4 mt5">
      <p className="lh-copy f3 tc mw7 center mb5">
        <span className="spree-blue fw6">Spree Commerce</span> is a complete
        modular, API-driven open source e-commerce solution built with Ruby on
        Rails.
      </p>

      <div className="mw8 center">
        <div className="flex flex-row flex-column-m mv4">
          <Section path="/api" title="API Guides" className="mr3">
            The REST API is designed to give developers a convenient way to
            access data contained within Spree. With a standard read/write
            interface to store data, it is now very simple to write third party
            applications (eg. iPhone) that can talk to your Spree store.
          </Section>

          <Section path="/developer" title="Developer Guides" className="ml3">
            This part of Spree’s documentation covers the technical aspects of
            Spree. If you are working with Rails and are building a Spree store,
            this is the documentation for you.
          </Section>
        </div>

        <div className="flex flex-row flex-column-m mb5">
          <Section path="/developer" title="User Guides" className="mr3">
            This documentation is intended for business owners and site
            administrators of Spree e-commerce sites. Everything you need to
            know to configure and manage your Spree store can be found here.
          </Section>

          <Section path="/developer" title="Release Notes" className="ml3">
            Each major new release of Spree has an accompanying set of release
            notes. The purpose of these notes is to provide a high level
            overview of what has changed since the previous version of Spree.
          </Section>
        </div>
      </div>

      <p className="lh-copy f4 pt3 tc mw7 center mt3">
        Guides are hosted and maintained by
        <br />
        <a
          href="https://sparksolutions.co/"
          target="_blank"
          rel="noopener"
          className="link spree-blue fw6"
        >
          <LogoSpark />
        </a>
      </p>
    </div>
  </Layout>
)

export default IndexPage
